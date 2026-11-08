import Foundation

/// Everything the client can throw, apart from `CancellationError` when the calling task is cancelled.
public enum CMSOrbitError: Error, Sendable, Equatable {
    /// The API key is missing or is not a public `cms_pk_` key.
    case invalidAPIKey(String)
    /// A secret `cms_sk_` key was given where it is not allowed. Secret keys must never ship in an app.
    case secretKeyNotAllowed
    /// `preview: true` was asked for, but the client has no preview key.
    case previewKeyRequired
    /// The base URL or a path could not be turned into a request URL.
    case invalidURL(String)
    /// `401`: the key was refused, has expired, or may not read that region or language.
    case unauthorized(message: String)
    /// `404`: nothing at that address, or no menu, global entry, taxonomy, region or language with that key.
    case notFound(message: String)
    /// `402`: the organisation's CMS Orbit trial or plan has ended, so delivery is paused. Never retried.
    case subscriptionInactive
    /// `429`: too many requests. Wait `retryAfter` seconds before trying again.
    case rateLimited(retryAfter: TimeInterval, message: String)
    /// Any other `4xx` answer, such as `400 bad_request`.
    case http(status: Int, code: String, message: String)
    /// A `5xx` answer, after the client's retries.
    case server(status: Int, message: String)
    /// The CMS could not be reached or did not answer in time, after the client's retries.
    case unavailable(message: String)
    /// The answer could not be decoded into the type asked for.
    case decoding(String)
    /// A GraphQL answer carried errors.
    case graphQL(code: String, message: String)

    /// The HTTP status, when the error came from an answer.
    public var status: Int? {
        switch self {
        case .unauthorized: return 401
        case .notFound: return 404
        case .subscriptionInactive: return 402
        case .rateLimited: return 429
        case .http(let status, _, _), .server(let status, _): return status
        default: return nil
        }
    }

    /// `true` when delivery is paused because the organisation's trial or plan has ended.
    public var isSubscriptionInactive: Bool {
        self == .subscriptionInactive
    }

    /// The API's error code, such as `not_found` or `rate_limited`.
    public var code: String {
        switch self {
        case .invalidAPIKey: return "invalid_api_key"
        case .secretKeyNotAllowed: return "secret_key_not_allowed"
        case .previewKeyRequired: return "preview_key_required"
        case .invalidURL: return "invalid_url"
        case .unauthorized: return "unauthorized"
        case .notFound: return "not_found"
        case .subscriptionInactive: return "subscription_inactive"
        case .rateLimited: return "rate_limited"
        case .http(_, let code, _), .graphQL(let code, _): return code
        case .server, .unavailable: return "unavailable"
        case .decoding: return "decoding_failed"
        }
    }
}

extension CMSOrbitError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidAPIKey(let message): return message
        case .secretKeyNotAllowed:
            return "A secret cms_sk_ key must never be used in an app. Use a public cms_pk_ key."
        case .previewKeyRequired: return "Previewing needs a previewKey on the client"
        case .subscriptionInactive:
            return "Delivery is paused because the organisation's CMS Orbit trial or plan has ended. Nothing is deleted, and it comes back as soon as an owner chooses a plan."
        case .invalidURL(let url): return "Not a valid URL: \(url)"
        case .unauthorized(let message), .notFound(let message), .unavailable(let message):
            return message
        case .rateLimited(_, let message), .http(_, _, let message), .server(_, let message), .graphQL(_, let message):
            return message
        case .decoding(let message): return "The answer could not be decoded: \(message)"
        }
    }
}
