import Foundation
import Testing
import CryptoKit
@testable import flactastic

// MARK: - Qobuz signature

@Test func qobuzSignatureMatchesLucida() {
    // The Lucida signing algorithm (qobuz/main.ts:117-141) for these inputs
    // produces a deterministic md5 hash. We compute it here in Swift two
    // independent ways and assert equality:
    //   1. Through QobuzAPI.signature(...)
    //   2. By manually concatenating params and md5'ing
    let api = QobuzAPI(appID: "950096963", appSecret: "test-secret")
    let params: [String: String] = [
        "track_id": "12345",
        "format_id": "27",
        "intent": "stream",
        "sample": "false",
        "app_id": "950096963",          // excluded from sig
        "user_auth_token": "abc"        // excluded from sig
    ]
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let result = api.signature(path: "track/getFileUrl", params: params, now: now)

    // Manual recomputation
    var manual = "trackgetFileUrl"
    for key in params.keys.sorted() {
        if key == "app_id" || key == "user_auth_token" { continue }
        manual += key + params[key]!
    }
    manual += "1700000000" + "test-secret"
    let expected = Insecure.MD5.hash(data: Data(manual.utf8))
        .map { String(format: "%02x", $0) }.joined()

    #expect(result.timestamp == 1_700_000_000)
    #expect(result.hash == expected)
    #expect(result.hash.count == 32)
}

@Test func qobuzSignatureExcludesAppIDAndAuthToken() {
    let api = QobuzAPI(appID: "X", appSecret: "secret")
    let withExtras: [String: String] = ["foo": "bar", "app_id": "ignored", "user_auth_token": "also-ignored"]
    let withoutExtras: [String: String] = ["foo": "bar"]
    let now = Date(timeIntervalSince1970: 1)
    let a = api.signature(path: "p", params: withExtras, now: now)
    let b = api.signature(path: "p", params: withoutExtras, now: now)
    #expect(a.hash == b.hash)
}

// MARK: - Deezer Blowfish

@Test func deezerKeyDerivation() {
    // For SNG_ID "12345":
    //   md5_hex("12345") = "827ccb0eea8a706c4c34a16891f84e7b"
    // key[i] = hex[i] ^ hex[i+16] ^ "g4el58wc0zvf9na1"[i]
    let key = DeezerCrypto.deriveKey(forTrackID: "12345")
    #expect(key.count == 16)

    // Independent recomputation
    let hex = "827ccb0eea8a706c4c34a16891f84e7b"
    let hexBytes = Array(hex.utf8)
    let secretBytes = Array("g4el58wc0zvf9na1".utf8)
    var expected = Data(count: 16)
    for i in 0..<16 {
        expected[i] = hexBytes[i] ^ hexBytes[i + 16] ^ secretBytes[i]
    }
    #expect(key == expected)
}

@Test func deezerBlowfishRoundTrip() throws {
    // Encrypt 2048 bytes with the same key + IV, then run our decrypt and
    // verify byte-for-byte identity.
    let key = DeezerCrypto.deriveKey(forTrackID: "999999")
    var plaintext = Data(count: 2048)
    for i in 0..<plaintext.count { plaintext[i] = UInt8(i & 0xff) }

    let cipher = blowfishCBCEncrypt(data: plaintext, key: key, iv: DeezerCrypto.iv)
    #expect(cipher.count == plaintext.count)

    var stripe = cipher
    DeezerCrypto.decryptStripe(&stripe, key: key)
    #expect(stripe == plaintext)
}

@Test func deezerStripeOnlyDecryptsEvery3rd() async throws {
    // Build a synthetic upstream of three 2048-byte stripes:
    //   stripe 0 = encrypted version of plaintext0
    //   stripe 1 = plaintext1 (passed through)
    //   stripe 2 = plaintext2 (passed through)
    let key = DeezerCrypto.deriveKey(forTrackID: "1")
    var p0 = Data(count: 2048); for i in 0..<2048 { p0[i] = UInt8(i & 0xff) }
    var p1 = Data(count: 2048); for i in 0..<2048 { p1[i] = UInt8((i + 1) & 0xff) }
    var p2 = Data(count: 2048); for i in 0..<2048 { p2[i] = UInt8((i + 2) & 0xff) }
    _ = (p0, p1, p2)

    let c0 = blowfishCBCEncrypt(data: p0, key: key, iv: DeezerCrypto.iv)

    let upstream = AsyncThrowingStream<Data, Error> { continuation in
        continuation.yield(c0)
        continuation.yield(p1)
        continuation.yield(p2)
        continuation.finish()
    }
    let decrypted = DeezerCrypto.decryptingStream(upstream: upstream, key: key)

    var collected = Data()
    for try await chunk in decrypted {
        collected.append(chunk)
    }
    #expect(collected.count == 3 * 2048)
    #expect(collected.subdata(in: 0..<2048) == p0)
    #expect(collected.subdata(in: 2048..<4096) == p1)
    #expect(collected.subdata(in: 4096..<6144) == p2)
}

@Test func deezerTrailingPartialStripeIsPassedThrough() async throws {
    // A trailing chunk smaller than 2048 must NOT be decrypted (matches Lucida
    // behaviour at main.ts:447-453: only when final.length >= 2048).
    let key = DeezerCrypto.deriveKey(forTrackID: "1")
    let trailing = Data([0xde, 0xad, 0xbe, 0xef])

    let upstream = AsyncThrowingStream<Data, Error> { continuation in
        continuation.yield(trailing)
        continuation.finish()
    }
    let decrypted = DeezerCrypto.decryptingStream(upstream: upstream, key: key)
    var collected = Data()
    for try await chunk in decrypted { collected.append(chunk) }
    #expect(collected == trailing)
}

// MARK: - Helpers

import CommonCrypto

/// Encrypt counterpart to DeezerCrypto.blowfishCBCDecrypt, used only by tests.
private func blowfishCBCEncrypt(data: Data, key: Data, iv: [UInt8]) -> Data {
    let bufSize = data.count + 8
    var out = Data(count: bufSize)
    var moved = 0
    let status: CCCryptorStatus = out.withUnsafeMutableBytes { outPtr -> CCCryptorStatus in
        data.withUnsafeBytes { inPtr -> CCCryptorStatus in
            key.withUnsafeBytes { keyPtr -> CCCryptorStatus in
                iv.withUnsafeBufferPointer { ivPtr -> CCCryptorStatus in
                    CCCrypt(
                        CCOperation(kCCEncrypt),
                        CCAlgorithm(kCCAlgorithmBlowfish),
                        CCOptions(0),
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
    precondition(status == kCCSuccess)
    out.removeSubrange(moved..<out.count)
    return out
}
