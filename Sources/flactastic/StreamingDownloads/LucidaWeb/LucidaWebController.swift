import Foundation
import WebKit
import AppKit
import Observation

/// Thin host for a hidden `WKWebView` pointed at https://lucida.to.
///
/// Why a WebView at all: lucida.to's `/api/load`, `/api/fetch/*`, and the file
/// CDN are all behind Cloudflare's bot challenge. A real browser passes the
/// JS challenge and obtains a `cf_clearance` cookie. Driving the page from
/// inside `WKWebView` (cookies + matching TLS fingerprint + UA) lets us hit
/// the same JSON API the website uses, with zero user setup.
///
/// All public methods are `async`; under the hood they bounce JSON through
/// `evaluateJavaScript`, calling the `__flac` helpers we inject on first load.
@MainActor
@Observable
final class LucidaWebController: NSObject {

    /// State machine. `ready` means the page finished loading *and* our
    /// helper script was injected — i.e. the bridge methods are usable.
    enum Phase: Equatable {
        case idle, loading, ready, failed(String)
    }

    private(set) var phase: Phase = .idle

    /// Append-only ring of debug events (navigation, bridge calls, errors).
    /// Capped at 200 entries so the debug window stays responsive on long
    /// sessions. Surfaced via the View → "Enable Debugging" pane.
    struct LogEntry: Identifiable, Hashable {
        let id = UUID()
        let timestamp = Date()
        let kind: Kind
        let message: String
        enum Kind: String { case nav, bridge, ok, error, info }
    }
    private(set) var log: [LogEntry] = []

    func addLog(_ kind: LogEntry.Kind, _ message: String) {
        log.append(LogEntry(kind: kind, message: message))
        if log.count > 200 { log.removeFirst(log.count - 200) }
    }

    func clearLog() { log.removeAll() }

    /// Continuations awaiting `.ready`. We collect them rather than poll.
    @ObservationIgnored
    private var readyWaiters: [CheckedContinuation<Void, Error>] = []

    let webView: WKWebView
    private static let entryURL = URL(string: "https://lucida.to/")!
    /// User-Agent we mirror for any out-of-WebView requests (so cookies +
    /// fingerprint stay consistent with the cleared session).
    static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 " +
        "(KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()  // persistent cookies across launches
        // Hidden frame; we never display it.
        self.webView = WKWebView(frame: .init(x: 0, y: 0, width: 1024, height: 768),
                                 configuration: config)
        super.init()
        webView.customUserAgent = Self.userAgent
        webView.navigationDelegate = self
        // Web Inspector access from the debug window (Right-click → Inspect
        // Element). Requires macOS 13.3+; harmless on older OSes.
        if #available(macOS 13.3, *) { webView.isInspectable = true }
        // Off-screen attach. WKWebView doesn't tick layout / JS reliably until
        // it's in a window; the simplest cure is a 1×1 hidden NSWindow.
        Self.host(webView)
    }

    // MARK: - Lifecycle

    /// Begin loading lucida.to (idempotent). Call from the app's bootstrap.
    func warmUp() {
        guard phase == .idle else { return }
        phase = .loading
        addLog(.nav, "load \(Self.entryURL.absoluteString)")
        webView.load(URLRequest(url: Self.entryURL))
    }

    /// Force a reload — useful from the debug pane after a CF challenge
    /// blocked the first attempt.
    func reload() {
        addLog(.nav, "reload (phase=\(phase))")
        phase = .loading
        webView.load(URLRequest(url: Self.entryURL))
    }

    /// Suspend until the bridge is usable. Throws if the load failed.
    func awaitReady() async throws {
        switch phase {
        case .ready: return
        case .failed(let msg): throw StreamerError.unavailable("Lucida unavailable: \(msg)")
        case .idle: warmUp(); fallthrough
        case .loading:
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                readyWaiters.append(cont)
            }
        }
    }

    private func resolveWaiters(_ result: Result<Void, Error>) {
        let waiters = readyWaiters
        readyWaiters.removeAll()
        for w in waiters { w.resume(with: result) }
    }

    // MARK: - JS bridge

    /// Run the helper expression and decode the JSON it resolves with.
    /// Helpers are defined in `bridgeScript` below; each takes care of
    /// success/error normalisation so callers see a consistent envelope.
    func callBridge<T: Decodable>(_ expr: String, as: T.Type = T.self) async throws -> T {
        try await awaitReady()
        addLog(.bridge, expr.prefix(220).description)
        do {
            let str = try await evaluateString(expr)
            guard let data = str.data(using: .utf8) else {
                throw StreamerError.decoding("non-utf8 bridge payload")
            }
            let env = try JSONDecoder().decode(BridgeEnvelope<T>.self, from: data)
            if !env.ok {
                addLog(.error, "bridge !ok: \(env.error ?? "<nil>")")
                throw StreamerError.unavailable(env.error ?? "lucida bridge error")
            }
            guard let v = env.value else {
                throw StreamerError.decoding("bridge ok=true but value missing")
            }
            addLog(.ok, "bridge ok (\(str.count) chars)")
            return v
        } catch {
            addLog(.error, "bridge threw: \(error)")
            throw error
        }
    }

    /// Run an async expression and return its resolved string value.
    ///
    /// `evaluateJavaScript` does NOT await Promises — it errors out with
    /// "result of an unsupported type". `callAsyncJavaScript` runs the body
    /// as an async function and awaits the returned Promise on the JS side
    /// before bridging the result back. The bridge helpers always resolve
    /// to a JSON-stringified envelope (see `bridgeScript`), so we narrow to
    /// `String` for Sendable safety.
    private func evaluateString(_ expr: String) async throws -> String {
        let body = "return await (\(expr));"
        return try await withCheckedThrowingContinuation { cont in
            webView.callAsyncJavaScript(
                body, arguments: [:], in: nil, in: .page
            ) { result in
                switch result {
                case .failure(let e): cont.resume(throwing: e)
                case .success(let value):
                    if let s = value as? String {
                        cont.resume(returning: s)
                    } else {
                        cont.resume(throwing: StreamerError.decoding(
                            "bridge expected String, got \(type(of: value))"
                        ))
                    }
                }
            }
        }
    }

    /// Synchronous-bodied script (used to install the helpers themselves).
    private func evaluateVoid(_ js: String) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            webView.evaluateJavaScript(js) { _, error in
                if let error { cont.resume(throwing: error); return }
                cont.resume(returning: ())
            }
        }
    }

    /// All cookies the WebView currently has for `lucida.to` (including
    /// every backend node). Used to share the cleared session with
    /// URLSession-backed downloads.
    func httpCookies() async -> [HTTPCookie] {
        await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
    }

    /// Start a `WKDownload` for the given request, using the cleared session.
    /// The returned download's delegate must be set by the caller before any
    /// data arrives — `WKWebView.startDownload` invokes the delegate
    /// synchronously for `decideDestination`.
    func startDownload(_ request: URLRequest) async -> WKDownload {
        await withCheckedContinuation { cont in
            webView.startDownload(using: request) { dl in cont.resume(returning: dl) }
        }
    }

    // MARK: - Helper script

    /// Injected once on first navigation. Defines `window.__flac.*` helpers
    /// that wrap the lucida.to fetch calls and return JSON-stringified
    /// `{ok, value?, error?}` envelopes — easier to bridge than raw promises.
    private static let bridgeScript: String = #"""
    (function () {
      if (window.__flac) return;
      const enc = encodeURIComponent;
      async function call(fn) {
        try {
          const value = await fn();
          return JSON.stringify({ ok: true, value });
        } catch (e) {
          return JSON.stringify({ ok: false, error: String(e && e.message || e) });
        }
      }
      window.__flac = {
        // Returns the lucida.to assignment for an external URL — useful as a
        // ping/health check.
        ping: () => call(async () => {
          const r = await fetch('/api/load?url=' + enc('https://lucida.to/'));
          return await r.json();
        }),
        // GET /api/load?url=<inner>; returns parsed JSON.
        loadGet: (innerPath) => call(async () => {
          const r = await fetch('/api/load?url=' + enc(innerPath));
          if (!r.ok) throw new Error('loadGet HTTP ' + r.status);
          return await r.json();
        }),
        // POST /api/load?url=/api/fetch/stream/v2 with the standard body.
        // `force` (server name from a previous response) skips re-assignment.
        streamV2: (body, force) => call(async () => {
          let u = '/api/load?url=' + enc('/api/fetch/stream/v2');
          if (force) u += '&force=' + enc(force);
          const r = await fetch(u, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(body),
          });
          if (!r.ok) throw new Error('streamV2 HTTP ' + r.status);
          return await r.json();
        }),
        // Poll a job: GET /api/load?url=/api/fetch/request/<handoff>&force=<srv>
        pollRequest: (handoff, server) => call(async () => {
          const inner = '/api/fetch/request/' + handoff;
          const u = '/api/load?url=' + enc(inner) + '&force=' + enc(server);
          const r = await fetch(u);
          if (!r.ok) throw new Error('pollRequest HTTP ' + r.status);
          return await r.json();
        }),
        // GET metadata (only used after isrc/songlink upgrades).
        metadata: (serviceURL) => call(async () => {
          const inner = '/api/fetch/metadata?url=' + enc(serviceURL);
          const r = await fetch('/api/load?url=' + enc(inner));
          if (!r.ok) throw new Error('metadata HTTP ' + r.status);
          return await r.json();
        }),
      };
    })();
    """#
}

private struct BridgeEnvelope<U: Decodable>: Decodable {
    let ok: Bool
    let value: U?
    let error: String?
}

// MARK: - Navigation delegate

extension LucidaWebController: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let url = MainActor.assumeIsolated { webView.url?.absoluteString } ?? "?"
        Task { @MainActor in
            self.addLog(.nav, "didFinish \(url)")
            do {
                try await self.evaluateVoid(Self.bridgeScript)
                self.phase = .ready
                self.addLog(.ok, "bridge installed; ready")
                self.resolveWaiters(.success(()))
            } catch {
                let msg = (error as NSError).localizedDescription
                self.phase = .failed(msg)
                self.addLog(.error, "bridge install failed: \(msg)")
                self.resolveWaiters(.failure(StreamerError.unavailable("Lucida bridge install failed: \(msg)")))
            }
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.recordNavFailure("didFail", error) }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.recordNavFailure("didFailProvisional", error) }
    }

    private func recordNavFailure(_ stage: String, _ error: Error) {
        let ns = error as NSError
        let detail = "\(stage) [\(ns.domain) \(ns.code)] \(ns.localizedDescription)"
        addLog(.error, detail)
        phase = .failed(ns.localizedDescription)
        resolveWaiters(.failure(error))
    }
}

// MARK: - Hidden window host

extension LucidaWebController {
    /// WKWebView only ticks JS reliably when attached to a window. We park it
    /// in a 1×1 transparent off-screen window — invisible, never key, no menu
    /// bar entry, just enough AppKit context to make the runtime happy.
    private static var hiddenHosts: [WKWebView: NSWindow] = [:]

    static func host(_ webView: WKWebView) {
        let window = NSWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: 1, height: 1),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.level = .normal
        window.contentView?.addSubview(webView)
        window.orderOut(nil)
        hiddenHosts[webView] = window
    }
}
