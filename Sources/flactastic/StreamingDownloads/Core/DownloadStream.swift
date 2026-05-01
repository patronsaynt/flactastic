import Foundation

/// Async byte stream returned by a `StreamerProvider` for a single track. The
/// `bytes` sequence yields `Data` chunks in the order the source delivers them;
/// the chunk size is opaque (the underlying transport, e.g. URLSession, picks
/// it). Consumers should treat the file as complete only when the sequence
/// terminates without throwing.
struct DownloadStream: Sendable {
    let bytes: AsyncThrowingStream<Data, Error>
    let mimeType: String
    /// Total payload size in bytes when the server advertises Content-Length.
    /// `nil` for chunked / unknown-length streams (the UI degrades to an
    /// indeterminate progress indicator).
    let sizeBytes: Int64?
    /// File extension (no leading dot) — "flac", "mp3", "m4a". Used for the
    /// staging temp file name and final destination path.
    let suggestedExtension: String

    init(
        bytes: AsyncThrowingStream<Data, Error>,
        mimeType: String,
        sizeBytes: Int64?,
        suggestedExtension: String
    ) {
        self.bytes = bytes
        self.mimeType = mimeType
        self.sizeBytes = sizeBytes
        self.suggestedExtension = suggestedExtension
    }
}

extension DownloadStream {
    /// Convenience adapter: wrap `URLSession.bytes(for:)` (which yields one
    /// byte at a time) into a chunked `Data` stream. We accumulate into 64KB
    /// chunks before yielding so downstream consumers (file write, decryptor)
    /// don't pay a per-byte overhead.
    static func from(
        urlSessionBytes asyncBytes: URLSession.AsyncBytes,
        mimeType: String,
        sizeBytes: Int64?,
        suggestedExtension: String,
        chunkSize: Int = 64 * 1024
    ) -> DownloadStream {
        let stream = AsyncThrowingStream<Data, Error> { continuation in
            let task = Task {
                do {
                    var buffer = Data(capacity: chunkSize)
                    for try await byte in asyncBytes {
                        buffer.append(byte)
                        if buffer.count >= chunkSize {
                            continuation.yield(buffer)
                            buffer = Data(capacity: chunkSize)
                        }
                        if Task.isCancelled { break }
                    }
                    if !buffer.isEmpty { continuation.yield(buffer) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        return DownloadStream(
            bytes: stream,
            mimeType: mimeType,
            sizeBytes: sizeBytes,
            suggestedExtension: suggestedExtension
        )
    }
}
