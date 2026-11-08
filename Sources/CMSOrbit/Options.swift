import Foundation

/// Where the client reads from.
public enum CMSEnvironment: Sendable, Hashable {
    /// `https://api.bifrostorbit.com/cms`
    case production
    /// `https://api-stage.bifrostorbit.com/cms`
    case staging
    /// Any other address, such as a self-hosted CMS Orbit.
    case custom(URL)

    public var baseURL: URL {
        switch self {
        case .production: return URL(string: "https://api.bifrostorbit.com/cms")!
        case .staging: return URL(string: "https://api-stage.bifrostorbit.com/cms")!
        case .custom(let url): return url
        }
    }
}

/// Options most calls take. Anything left `nil` uses the client's defaults.
public struct CMSRequestOptions: Sendable, Hashable {
    /// Region key or short code, such as `germany` or `de`.
    public var region: String?
    /// Language code, such as `de-DE`.
    public var locale: String?
    /// Read drafts. Needs a preview key, which only server-side Swift may hold.
    public var preview: Bool
    /// Refuse every fallback: the content must exist in the language and region asked for.
    public var strict: Bool
    /// Replace Reference fields' entry ids with the entries they point at.
    public var includeReferences: Bool

    public init(region: String? = nil, locale: String? = nil, preview: Bool = false, strict: Bool = false, includeReferences: Bool = false) {
        self.region = region
        self.locale = locale
        self.preview = preview
        self.strict = strict
        self.includeReferences = includeReferences
    }
}

/// Extra content to add to a list.
public enum CMSInclude: String, Sendable, Hashable, CaseIterable {
    /// Each entry's fields.
    case fields
    /// Fields, with references replaced by the entries they point at.
    case references
}

public enum CMSListSort: String, Sendable, Hashable, CaseIterable {
    case sortOrder
    case name
    case nameDescending = "-name"
    case publishedAt
    case publishedAtDescending = "-publishedAt"
    case updatedAt
    case updatedAtDescending = "-updatedAt"
}

/// What to list, for ``CMSOrbitClient/list(_:)``.
public struct CMSListOptions: Sendable, Hashable {
    /// The content type key, such as `product`.
    public var type: String
    public var region: String?
    public var locale: String?
    public var preview: Bool
    public var include: Set<CMSInclude>
    /// 1 or more.
    public var page: Int?
    /// 1 to 100. The API's default is 20.
    public var perPage: Int?
    /// Exact matches on fields, sent as `filter[<field>]=<value>`.
    public var filter: [String: String]
    /// Entries whose `tags` field contains this value.
    public var tag: String?
    /// Entries whose `category` field equals this value.
    public var category: String?
    public var sort: CMSListSort?
    /// Entries whose name contains this text, ignoring case.
    public var query: String?

    public init(
        type: String,
        region: String? = nil,
        locale: String? = nil,
        preview: Bool = false,
        include: Set<CMSInclude> = [],
        page: Int? = nil,
        perPage: Int? = nil,
        filter: [String: String] = [:],
        tag: String? = nil,
        category: String? = nil,
        sort: CMSListSort? = nil,
        query: String? = nil
    ) {
        self.type = type
        self.region = region
        self.locale = locale
        self.preview = preview
        self.include = include
        self.page = page
        self.perPage = perPage
        self.filter = filter
        self.tag = tag
        self.category = category
        self.sort = sort
        self.query = query
    }
}

/// Which banners to read, for ``CMSOrbitClient/banners(_:loggedIn:options:)``.
public enum CMSBannerScope: Sendable, Hashable {
    /// Banners targeting this page.
    case path(String)
    /// Banners live on any page, each with the `paths` it targets.
    case everyPage
}
