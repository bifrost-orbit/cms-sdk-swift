import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Reads published content from the CMS Orbit delivery API.
///
/// ```swift
/// let cms = try CMSOrbitClient(apiKey: "cms_pk_...", region: "germany")
/// let page = try await cms.page("/gear/fjell-gtx-boot")
/// ```
public final class CMSOrbitClient: Sendable {
    /// The SDK's version, sent in the `User-Agent` header.
    public static let version = "0.2.0"

    /// The delivery API address, such as `https://api.bifrostorbit.com/cms/api/cdn/v1`.
    public let apiURL: URL
    /// The CMS address without the API path, such as `https://api.bifrostorbit.com/cms`.
    public let origin: URL
    public let defaultRegion: String?
    public let defaultLocale: String?
    public let timeout: TimeInterval
    public let retries: Int

    private let apiKey: String
    private let previewKey: String?
    private let session: URLSession

    private static let retryDelays: [UInt64] = [250, 750, 2000]

    /// Creates a client.
    ///
    /// - Parameters:
    ///   - apiKey: A public delivery key, starting with `cms_pk_`. Secret `cms_sk_` keys are refused.
    ///   - environment: Production, staging or your own address.
    ///   - baseURL: Overrides the environment's address, such as `https://api.bifrostorbit.com/cms`.
    ///   - region: The region to read when a call does not name one, such as `germany`.
    ///   - locale: The language to read when a call does not name one, such as `de-DE`.
    ///   - previewKey: A secret `cms_sk_` key for reading drafts. Server-side Swift only: refused on iOS, tvOS, watchOS and visionOS.
    ///   - timeout: Seconds to wait for each attempt. Default 5.
    ///   - retries: How many times to retry a failed connection or a `5xx` answer. Default 2.
    ///   - session: The `URLSession` to use, for example one with a custom cache.
    public init(
        apiKey: String,
        environment: CMSEnvironment = .production,
        baseURL: URL? = nil,
        region: String? = nil,
        locale: String? = nil,
        previewKey: String? = nil,
        timeout: TimeInterval = 5,
        retries: Int = 2,
        session: URLSession = .shared
    ) throws {
        try Self.validatePublicKey(apiKey)
        if let previewKey {
            try Self.validatePreviewKey(previewKey)
        }

        let base = (baseURL ?? environment.baseURL).absoluteString
        guard let api = URL(string: Self.apiBase(base)), api.scheme != nil, api.host != nil else {
            throw CMSOrbitError.invalidURL(base)
        }
        let originString = api.absoluteString.replacingOccurrences(of: #"/api/cdn/v\d+$"#, with: "", options: .regularExpression)
        guard let origin = URL(string: originString) else { throw CMSOrbitError.invalidURL(base) }

        self.apiURL = api
        self.origin = origin
        self.apiKey = apiKey
        self.previewKey = previewKey
        self.defaultRegion = region
        self.defaultLocale = locale
        self.timeout = timeout
        self.retries = max(0, retries)
        self.session = session
    }

    static func validatePublicKey(_ key: String) throws {
        if key.isEmpty { throw CMSOrbitError.invalidAPIKey("An apiKey is required") }
        if key.hasPrefix("cms_sk_") { throw CMSOrbitError.secretKeyNotAllowed }
        if !key.hasPrefix("cms_pk_") {
            throw CMSOrbitError.invalidAPIKey("Use a public delivery key, starting with cms_pk_, from Configuration › API keys")
        }
    }

    static func validatePreviewKey(_ key: String) throws {
        #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        throw CMSOrbitError.secretKeyNotAllowed
        #else
        if !key.hasPrefix("cms_sk_") {
            throw CMSOrbitError.invalidAPIKey("A previewKey is a secret delivery key, starting with cms_sk_")
        }
        #endif
    }

    static func apiBase(_ baseURL: String) -> String {
        var trimmed = baseURL
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        if trimmed.range(of: #"/api/cdn/v\d+$"#, options: .regularExpression) != nil { return trimmed }
        if trimmed.hasSuffix("/api/cdn") { return "\(trimmed)/v1" }
        return "\(trimmed)/api/cdn/v1"
    }

    /// The preview token in an address the CMS editor opened, such as `https://northwilds.com/trips/lofoten-ridge-walk?preview=eyJ…`.
    public static func previewToken(from url: URL) -> String? {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let value = items.first(where: { $0.name == "preview" })?.value ?? items.first(where: { $0.name == "token" })?.value
        return value?.isEmpty == false ? value : nil
    }

    // MARK: - Pages

    /// One page by its address. Throws ``CMSOrbitError/notFound(message:)`` when nothing is there.
    public func page(_ path: String, options: CMSRequestOptions = .init()) async throws -> CMSPage {
        var page = try await send(CMSPage.self, "/content", query: pageQuery(path, options), preview: options.preview)
        page.meta.references = options.includeReferences
        return page
    }

    /// One page by its address, or `nil` when nothing is there.
    public func findPage(_ path: String, options: CMSRequestOptions = .init()) async throws -> CMSPage? {
        try await orNil { try await self.page(path, options: options) }
    }

    /// One page by its address, decoded into your own type.
    public func content<T: Decodable>(_ type: T.Type, path: String, options: CMSRequestOptions = .init()) async throws -> T {
        try await send(T.self, "/content", query: pageQuery(path, options), preview: options.preview)
    }

    /// Says what an address is: a page, a redirect, gone or not found. Call it before showing a page.
    ///
    /// - Parameter referrer: The address of the page that linked here, recorded with addresses that are not found.
    public func resolve(_ path: String, referrer: String? = nil, options: CMSRequestOptions = .init()) async throws -> CMSResolution {
        let body = try await send(
            ResolveBody.self,
            "/resolve",
            query: pageQuery(path, options),
            preview: options.preview,
            headers: referrer.map { ["x-cms-referrer": $0] } ?? [:],
            accepting: [404, 410]
        )
        switch body.kind {
        case "page":
            guard var page = body.page else { throw CMSOrbitError.decoding("A page answer had no page") }
            page.meta.references = options.includeReferences
            return .page(page)
        case "redirect":
            guard let destination = body.destination, let status = body.statusCode else {
                throw CMSOrbitError.decoding("A redirect answer had no destination")
            }
            return .redirect(CMSRedirect(
                to: destination,
                status: status,
                permanent: body.permanent ?? (status == 301 || status == 308),
                hops: body.hops ?? 0
            ))
        case "gone":
            return .gone
        default:
            return .notFound
        }
    }

    // MARK: - Site-wide content

    /// A menu, by its key.
    public func navigation(_ key: String, options: CMSRequestOptions = .init()) async throws -> CMSNavigation {
        try await send(CMSNavigation.self, "/navigation", query: [("key", key)] + scope(options), preview: options.preview)
    }

    /// A menu, or `nil` when there is none with that key.
    public func findNavigation(_ key: String, options: CMSRequestOptions = .init()) async throws -> CMSNavigation? {
        try await orNil { try await self.navigation(key, options: options) }
    }

    /// A global entry, such as the footer, by its key.
    public func global(_ key: String, options: CMSRequestOptions = .init()) async throws -> CMSGlobal {
        try await send(CMSGlobal.self, "/global", query: globalQuery(key, options), preview: options.preview)
    }

    /// A global entry decoded into your own type.
    public func global<T: Decodable>(_ type: T.Type, key: String, options: CMSRequestOptions = .init()) async throws -> T {
        try await send(T.self, "/global", query: globalQuery(key, options), preview: options.preview)
    }

    /// A global entry, or `nil` when there is none with that key.
    public func findGlobal(_ key: String, options: CMSRequestOptions = .init()) async throws -> CMSGlobal? {
        try await orNil { try await self.global(key, options: options) }
    }

    // MARK: - Lists

    /// Entries of one content type, with their fields as ``JSONValue`` when asked for.
    public func list(_ options: CMSListOptions) async throws -> CMSContentList<JSONValue> {
        try await list(options, fields: JSONValue.self)
    }

    /// Entries of one content type, with their fields decoded into your own type.
    public func list<Fields: Decodable & Sendable>(_ options: CMSListOptions, fields: Fields.Type) async throws -> CMSContentList<Fields> {
        var query: [(String, String?)] = [("type", options.type)]
        query += scope(region: options.region, locale: options.locale)
        query += [
            ("page", options.page.map(String.init)),
            ("perPage", options.perPage.map(String.init)),
            ("tag", options.tag),
            ("category", options.category),
            ("sort", options.sort?.rawValue),
            ("q", options.query),
            ("include", options.include.map(\.rawValue).sorted().joined(separator: ",")),
        ]
        query += options.filter.keys.sorted().map { ("filter[\($0)]", options.filter[$0]) }
        return try await send(CMSContentList<Fields>.self, "/list", query: query, preview: options.preview)
    }

    // MARK: - Regions and taxonomies

    /// The regions the key may read, with their languages.
    public func regions() async throws -> [CMSRegion] {
        try await send([CMSRegion].self, "/regions", query: [], preview: false)
    }

    /// The languages of a region, or of the client's default region. With neither, every region's languages.
    public func locales(region: String? = nil) async throws -> [CMSLocale] {
        let regions = try await regions()
        guard let wanted = region ?? defaultRegion else { return regions.flatMap(\.locales) }
        return regions.first(where: { $0.key == wanted })?.locales ?? []
    }

    /// A taxonomy and its terms, in their set order.
    public func taxonomy(_ key: String, locale: String? = nil) async throws -> CMSTaxonomy {
        let encoded = key.addingPercentEncoding(withAllowedCharacters: Self.unreserved) ?? key
        return try await send(CMSTaxonomy.self, "/taxonomies/\(encoded)", query: [("locale", locale)], preview: false)
    }

    /// The space's content types and components, with their fields.
    public func schema() async throws -> CMSSchema {
        try await send(CMSSchema.self, "/schema", query: [], preview: false)
    }

    // MARK: - Campaigns and shop

    /// Banners live now for a page, or for every page.
    public func banners(_ scope: CMSBannerScope, loggedIn: Bool = false, options: CMSRequestOptions = .init()) async throws -> CMSTimed<CMSBanner> {
        var query: [(String, String?)]
        switch scope {
        case .path(let path): query = [("path", path)]
        case .everyPage: query = [("everyPage", "true")]
        }
        query.append(("loggedIn", loggedIn ? "true" : nil))
        return try await send(CMSTimed<CMSBanner>.self, "/banners", query: query + self.scope(options), preview: options.preview)
    }

    /// Popups live now for a page and the visitor's sign-in state, highest priority first.
    public func popups(path: String, loggedIn: Bool = false, options: CMSRequestOptions = .init()) async throws -> CMSTimed<CMSPopup> {
        let query: [(String, String?)] = [("path", path), ("loggedIn", loggedIn ? "true" : nil)]
        return try await send(CMSTimed<CMSPopup>.self, "/popups", query: query + scope(options), preview: options.preview)
    }

    /// Shop products with live prices and stock.
    ///
    /// - Parameter filter: A taxonomy term value. Products tagged with it in any taxonomy field match.
    public func products(page: Int? = nil, perPage: Int? = nil, filter: String? = nil, options: CMSRequestOptions = .init()) async throws -> CMSProductPage {
        let query: [(String, String?)] = scope(options) + [
            ("page", page.map(String.init)),
            ("perPage", perPage.map(String.init)),
            ("filter", filter),
        ]
        return try await send(CMSProductPage.self, "/products", query: query, preview: options.preview)
    }

    // MARK: - Search engines

    /// The index of every region and language's sitemap.
    public func sitemapIndex() async throws -> CMSSitemapIndex {
        try await send(CMSSitemapIndex.self, "/sitemap", query: [], preview: false)
    }

    /// One region's sitemap. Uses the client's default region when `region` is `nil`.
    public func sitemap(region: String? = nil, locale: String? = nil, page: Int? = nil) async throws -> CMSSitemap {
        guard let region = region ?? defaultRegion else {
            throw CMSOrbitError.invalidURL("A sitemap needs a region, or a default region on the client")
        }
        let query: [(String, String?)] = [("region", region), ("locale", locale), ("page", page.map(String.init))]
        return try await send(CMSSitemap.self, "/sitemap", query: query, preview: false)
    }

    /// The environment's robots.txt.
    public func robots() async throws -> CMSRobots {
        try await send(CMSRobots.self, "/robots", query: [], preview: false)
    }

    // MARK: - Preview

    /// Checks a preview token from the CMS editor and says which entry it is for, with the editor's saved draft.
    ///
    /// Tokens last an hour. An invalid or expired token throws ``CMSOrbitError/unauthorized(message:)``.
    public func verifyPreview(token: String) async throws -> CMSPreviewSession {
        let url = try makeURL(origin.absoluteString + "/preview", query: [("token", token)])
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        return try await perform(request, as: CMSPreviewSession.self, accepting: [], retries: 0)
    }

    // MARK: - GraphQL and raw requests

    /// Runs a GraphQL query and decodes its `data` into your own type.
    public func graphql<T: Decodable>(
        _ query: String,
        variables: [String: JSONValue]? = nil,
        operationName: String? = nil,
        preview: Bool = false,
        as type: T.Type
    ) async throws -> T {
        let url = try makeURL(origin.absoluteString + "/api/cdn/graphql", query: [])
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("Bearer \(try key(preview: preview))", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONEncoder().encode(GraphQLRequest(query: query, variables: variables, operationName: operationName))

        let (data, response) = try await load(request)
        let body = try? JSONDecoder().decode(GraphQLBody<T>.self, from: data)
        let first = body?.errors?.first
        switch response.statusCode {
        case 401: throw CMSOrbitError.unauthorized(message: first?.message ?? "The API key was refused")
        case 402: throw CMSOrbitError.subscriptionInactive
        case 429:
            throw CMSOrbitError.rateLimited(retryAfter: Self.retryAfter(response), message: first?.message ?? "Too many requests")
        case 500...: throw CMSOrbitError.server(status: response.statusCode, message: first?.message ?? "The CMS returned \(response.statusCode)")
        default: break
        }
        if let first {
            throw CMSOrbitError.graphQL(code: first.extensions?.code ?? "graphql_error", message: first.message)
        }
        do {
            return try JSONDecoder().decode(GraphQLData<T>.self, from: data).data
        } catch {
            throw CMSOrbitError.decoding(String(describing: error))
        }
    }

    /// Reads any delivery endpoint and decodes its `data` into your own type, for endpoints this SDK does not cover yet.
    ///
    /// - Parameter path: The endpoint, such as `/content`.
    public func get<T: Decodable>(_ type: T.Type, path: String, query: [String: String] = [:], preview: Bool = false) async throws -> T {
        try await send(T.self, path, query: query.keys.sorted().map { ($0, query[$0]) }, preview: preview)
    }

    // MARK: - Internals

    static let userAgent = "CMSOrbit-Swift/\(version)"

    private static let unreserved: CharacterSet = {
        var set = CharacterSet()
        set.insert(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return set
    }()

    private func scope(_ options: CMSRequestOptions) -> [(String, String?)] {
        scope(region: options.region, locale: options.locale)
    }

    private func scope(region: String?, locale: String?) -> [(String, String?)] {
        [("region", region ?? defaultRegion), ("locale", locale ?? defaultLocale)]
    }

    private func pageQuery(_ path: String, _ options: CMSRequestOptions) -> [(String, String?)] {
        [("url", path)] + scope(options) + [
            ("strict", options.strict ? "true" : nil),
            ("include", options.includeReferences ? "references" : nil),
        ]
    }

    private func globalQuery(_ key: String, _ options: CMSRequestOptions) -> [(String, String?)] {
        [("key", key)] + scope(options) + [
            ("strict", options.strict ? "true" : nil),
            ("include", options.includeReferences ? "references" : nil),
        ]
    }

    private func key(preview: Bool) throws -> String {
        guard preview else { return apiKey }
        guard let previewKey else { throw CMSOrbitError.previewKeyRequired }
        return previewKey
    }

    private func orNil<T>(_ body: () async throws -> T) async throws -> T? {
        do {
            return try await body()
        } catch CMSOrbitError.notFound {
            return nil
        }
    }

    private func makeURL(_ base: String, query: [(String, String?)]) throws -> URL {
        let pairs = query.compactMap { name, value -> String? in
            guard let value, !value.isEmpty else { return nil }
            let encodedName = name.addingPercentEncoding(withAllowedCharacters: Self.unreserved) ?? name
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: Self.unreserved) ?? value
            return "\(encodedName)=\(encodedValue)"
        }
        let string = pairs.isEmpty ? base : "\(base)?\(pairs.joined(separator: "&"))"
        guard let url = URL(string: string) else { throw CMSOrbitError.invalidURL(string) }
        return url
    }

    private func send<T: Decodable>(
        _ type: T.Type,
        _ path: String,
        query: [(String, String?)],
        preview: Bool,
        headers: [String: String] = [:],
        accepting: Set<Int> = []
    ) async throws -> T {
        let key = try key(preview: preview)
        let url = try makeURL(apiURL.absoluteString + path, query: query + [("draft", preview ? "true" : nil)])
        var request = URLRequest(
            url: url,
            cachePolicy: preview ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy,
            timeoutInterval: timeout
        )
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        return try await perform(request, as: T.self, accepting: accepting, retries: retries)
    }

    private func perform<T: Decodable>(_ request: URLRequest, as type: T.Type, accepting: Set<Int>, retries: Int) async throws -> T {
        var lastError: Error = CMSOrbitError.unavailable(message: "The CMS could not be reached")
        for attempt in 0...retries {
            if attempt > 0 {
                let delay = Self.retryDelays[min(attempt - 1, Self.retryDelays.count - 1)]
                try await Task.sleep(nanoseconds: delay * 1_000_000)
            }
            let data: Data
            let response: HTTPURLResponse
            do {
                (data, response) = try await load(request)
            } catch let error as CMSOrbitError {
                lastError = error
                continue
            }

            if (200..<300).contains(response.statusCode) || accepting.contains(response.statusCode) {
                do {
                    return try JSONDecoder().decode(Envelope<T>.self, from: data).data
                } catch {
                    throw CMSOrbitError.decoding(String(describing: error))
                }
            }

            let (code, message) = Self.errorDetails(data, status: response.statusCode)
            switch response.statusCode {
            case 500...:
                lastError = CMSOrbitError.server(status: response.statusCode, message: message)
                continue
            case 401: throw CMSOrbitError.unauthorized(message: message)
            case 402: throw CMSOrbitError.subscriptionInactive
            case 404: throw CMSOrbitError.notFound(message: message)
            case 429: throw CMSOrbitError.rateLimited(retryAfter: Self.retryAfter(response), message: message)
            default: throw CMSOrbitError.http(status: response.statusCode, code: code ?? "error", message: message)
            }
        }
        throw lastError
    }

    private func load(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try Task.checkCancellation()
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw CMSOrbitError.unavailable(message: "The CMS did not answer over HTTP")
            }
            return (data, http)
        } catch let error as CMSOrbitError {
            throw error
        } catch {
            if Task.isCancelled { throw CancellationError() }
            if (error as? URLError)?.code == .timedOut {
                throw CMSOrbitError.unavailable(message: "The CMS did not answer within \(Self.seconds(timeout))")
            }
            throw CMSOrbitError.unavailable(message: "The CMS could not be reached")
        }
    }

    private static func seconds(_ value: TimeInterval) -> String {
        value.rounded() == value ? "\(Int(value))s" : "\(value)s"
    }

    private static func retryAfter(_ response: HTTPURLResponse) -> TimeInterval {
        guard let header = response.value(forHTTPHeaderField: "Retry-After"), let seconds = Double(header), seconds > 0 else {
            return 60
        }
        return seconds
    }

    private static func errorDetails(_ data: Data, status: Int) -> (code: String?, message: String) {
        let fallback = "The CMS returned \(status)"
        guard let body = try? JSONDecoder().decode(JSONValue.self, from: data) else { return (nil, fallback) }
        if let error = body["error"], case .object = error {
            return (error["code"]?.stringValue, error["message"]?.stringValue ?? fallback)
        }
        return (body["error"]?.stringValue, body["message"]?.stringValue ?? fallback)
    }
}

private struct Envelope<T: Decodable>: Decodable {
    let data: T
}

private struct ResolveBody: Decodable {
    let kind: String
    let page: CMSPage?
    let destination: String?
    let statusCode: Int?
    let permanent: Bool?
    let hops: Int?
}

private struct GraphQLRequest: Encodable {
    let query: String
    let variables: [String: JSONValue]?
    let operationName: String?
}

private struct GraphQLError: Decodable {
    struct Extensions: Decodable {
        let code: String?
    }

    let message: String
    let extensions: Extensions?
}

private struct GraphQLBody<T: Decodable>: Decodable {
    let errors: [GraphQLError]?
}

private struct GraphQLData<T: Decodable>: Decodable {
    let data: T
}
