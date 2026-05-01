import Foundation
import CommonCrypto
import CryptoKit

/// Deezer's "BF_CBC_STRIPE" payload format:
/// the body is a sequence of 2048-byte chunks. Every 3rd chunk (indices 0, 3,
/// 6, …) is encrypted with Blowfish-CBC. Every other chunk is plaintext. The
/// final chunk may be shorter than 2048 bytes; if it's < 2048, it's left
/// untouched. Each encrypted chunk uses the same fixed IV and the same key
/// derived from the track id.
///
/// Mirrors the algorithm in `Resources/lucida/src/streamers/deezer/main.ts:409-470`.
enum DeezerCrypto {
    /// 16-byte Blowfish secret used as the third XOR operand when deriving a
    /// per-track key. Public Deezer client constant.
    static let blowfishSecret = "g4el58wc0zvf9na1"

    /// Fixed 8-byte IV used for every encrypted chunk. Public Deezer client constant.
    static let iv: [UInt8] = [0, 1, 2, 3, 4, 5, 6, 7]

    /// Stripe period — every Nth chunk is encrypted (1 of every 3).
    static let stripePeriod = 3

    /// Stripe chunk size — encrypted slice within a 2048-byte window.
    /// Lucida uses the entire 2048 bytes for the encrypted portion.
    static let chunkSize = 2048

    /// Derives the 16-byte Blowfish key for a given Deezer track id (`SNG_ID`
    /// as a string). Algorithm:
    ///
    ///   hash = md5_hex(songID)            // 32 ASCII chars
    ///   key[i] = hash[i] ^ hash[i+16] ^ blowfishSecret[i]   for i in 0..<16
    static func deriveKey(forTrackID id: String) -> Data {
        let digest = Insecure.MD5.hash(data: Data(id.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        let hashBytes = Array(hex.utf8)            // 32 bytes
        let secretBytes = Array(blowfishSecret.utf8) // 16 bytes
        precondition(hashBytes.count == 32 && secretBytes.count == 16,
                     "Deezer key derivation prerequisites broken")
        var key = Data(count: 16)
        for i in 0..<16 {
            key[i] = hashBytes[i] ^ hashBytes[i + 16] ^ secretBytes[i]
        }
        return key
    }

    /// Decrypts one 2048-byte stripe in-place. Returns `nil` and leaves the
    /// chunk untouched if the input length isn't exactly 2048 bytes.
    static func decryptStripe(_ chunk: inout Data, key: Data) {
        guard chunk.count == chunkSize else { return }
        let decrypted = blowfishCBCDecrypt(data: chunk, key: key)
        if let decrypted, decrypted.count >= chunk.count {
            chunk.replaceSubrange(0..<chunk.count, with: decrypted.prefix(chunk.count))
        }
    }

    /// Raw Blowfish-CBC decrypt via CommonCrypto. Returns plaintext on success
    /// or `nil` if `CCCrypt` reports an error.
    ///
    /// Notes on options:
    ///   - We pass `kCCOptionECBMode` *off* (default = CBC) and no padding bit
    ///     so the output length matches the input length. Deezer's stripe is
    ///     pre-aligned to 8 bytes (2048 = 256 × 8), so PKCS7 padding would be
    ///     wrong here.
    static func blowfishCBCDecrypt(data: Data, key: Data) -> Data? {
        let bufSize = data.count + 8 // tiny slack just in case
        var out = Data(count: bufSize)
        var moved = 0

        let status: CCCryptorStatus = out.withUnsafeMutableBytes { outPtr -> CCCryptorStatus in
            data.withUnsafeBytes { inPtr -> CCCryptorStatus in
                key.withUnsafeBytes { keyPtr -> CCCryptorStatus in
                    iv.withUnsafeBufferPointer { ivPtr -> CCCryptorStatus in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmBlowfish),
                            CCOptions(0), // CBC + no padding
                            keyPtr.baseAddress, key.count,
                            ivPtr.baseAddress,
                            inPtr.baseAddress, data.count,
                            outPtr.baseAddress, bufSize,
                            &moved
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        out.removeSubrange(moved..<out.count)
        return out
    }

    /// Wraps an upstream stream of arbitrary-sized `Data` chunks and yields
    /// chunks of the same total payload, but with every Nth 2048-byte stripe
    /// decrypted. The transformation is fully streaming: we never hold more
    /// than ~2048 bytes of input in memory.
    static func decryptingStream(
        upstream: AsyncThrowingStream<Data, Error>,
        key: Data
    ) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var pending = Data()
                    var stripeIndex = 0
                    pending.reserveCapacity(chunkSize)

                    for try await incoming in upstream {
                        if Task.isCancelled { break }
                        pending.append(incoming)

                        // Drain as many full 2048-byte stripes as we have.
                        while pending.count >= chunkSize {
                            var stripe = pending.prefix(chunkSize)
                            pending.removeSubrange(0..<chunkSize)
                            // Re-base the slice so its indices start at 0.
                            stripe = Data(stripe)

                            if stripeIndex % stripePeriod == 0 {
                                decryptStripe(&stripe, key: key)
                            }
                            continuation.yield(stripe)
                            stripeIndex += 1
                        }
                    }

                    // The trailing partial chunk is never encrypted (Lucida
                    // matches: it only decrypts when buf.length == chunkSize).
                    if !pending.isEmpty { continuation.yield(pending) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
