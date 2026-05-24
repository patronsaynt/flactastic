import SwiftUI

/// Surfaces the hidden Lucida WebView in a modal sheet when Cloudflare's
/// Turnstile challenge requires a real user click. The checkbox lives in a
/// cross-origin iframe Cloudflare actively guards against synthetic events,
/// so a one-tap, in-app prompt is the most reliable path. The sheet
/// auto-dismisses once `controller.phase` reaches `.ready`.
struct LucidaChallengeSheet: View {
    @Environment(LucidaWebController.self) private var controller
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.shield")
                    .font(.title3)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Verify with Lucida")
                        .font(.headline)
                    Text("Cloudflare needs a quick human check before downloads can start. Click the checkbox below — this window will close automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Reload") { controller.reload() }
            }
            .padding(12)
            .background(.bar)

            LucidaWebHost(webView: controller.webView)
                .frame(minWidth: 520, minHeight: 460)
        }
        .frame(width: 560, height: 540)
        .onChange(of: controller.phase) { _, newPhase in
            if newPhase == .ready { dismiss() }
        }
    }
}
