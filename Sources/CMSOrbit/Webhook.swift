#if canImport(CryptoKit)
import CryptoKit
import Foundation

/// A webhook message from CMS Orbit that passed ``CMSWebhook/parse(secret:timestamp:signature:body:now:)``.
public struct CMSWebhookMessage: Sendable, Equatable {
    /// Such as `content.published`, `navigation.changed` or `webhook.test`.
    public var event: String
    public var data: [String: JSONValue]

    public init(event: String, data: [String: JSONValue] = [:]) {
        self.event = event
        self.data = data
    }
}

// [EXPLAIN-D525]
/// Checks webhook messages from CMS Orbit on a Swift server, with the same rules as the JavaScript SDK's webhook handler.
public enum CMSWebhook {
    /// Messages whose `x-orbit-timestamp` is further than this from the clock are refused.
    public static let maxAge: TimeInterval = 5 * 60

    public static let timestampHeader = "x-orbit-timestamp"
    public static let signatureHeader = "x-orbit-signature"

    /// True when `signature`, the `x-orbit-signature` header, is the HMAC-SHA256 of `timestamp.body` keyed with the
    /// webhook secret, and `timestamp`, the `x-orbit-timestamp` header in milliseconds, is within five minutes of `now`.
    /// Pass the raw body, before any JSON parsing. An empty secret never verifies.
    public static func verify(secret: String, timestamp: String, signature: String, body: Data, now: Date = Date()) -> Bool {
        guard !secret.isEmpty, !timestamp.isEmpty, timestamp.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
              let sent = Int64(timestamp)
        else { return false }
        var signed = Data(timestamp.utf8)
        signed.append(UInt8(ascii: "."))
        signed.append(body)
        let digest = HMAC<SHA256>.authenticationCode(for: signed, using: SymmetricKey(data: Data(secret.utf8)))
        let expected = Array(digest.map { String(format: "%02x", $0) }.joined().utf8)
        let given = Array(signature.utf8)
        guard expected.count == given.count else { return false }
        var difference: UInt8 = 0
        for index in expected.indices {
            difference |= expected[index] ^ given[index]
        }
        guard difference == 0 else { return false }
        return abs(now.timeIntervalSince1970 * 1000 - Double(sent)) <= maxAge * 1000
    }

    public static func verify(secret: String, timestamp: String, signature: String, body: String, now: Date = Date()) -> Bool {
        verify(secret: secret, timestamp: timestamp, signature: signature, body: Data(body.utf8), now: now)
    }

    /// Verifies a message and answers its `event` and `data`, or `nil` when it is not genuine, is too old or is not JSON.
    public static func parse(secret: String, timestamp: String, signature: String, body: Data, now: Date = Date()) -> CMSWebhookMessage? {
        guard verify(secret: secret, timestamp: timestamp, signature: signature, body: body, now: now),
              case .object(let message)? = try? JSONDecoder().decode(JSONValue.self, from: body)
        else { return nil }
        let event: String
        if case .string(let value)? = message["event"] { event = value } else { event = "" }
        let data: [String: JSONValue]
        if case .object(let value)? = message["data"] { data = value } else { data = [:] }
        return CMSWebhookMessage(event: event, data: data)
    }

    public static func parse(secret: String, timestamp: String, signature: String, body: String, now: Date = Date()) -> CMSWebhookMessage? {
        parse(secret: secret, timestamp: timestamp, signature: signature, body: Data(body.utf8), now: now)
    }
}
#endif
