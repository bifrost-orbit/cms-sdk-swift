import Foundation

/// Rich text arrives as an HTML string.
public typealias CMSRichText = String

/// An image or file from an Asset or Assets field.
public struct CMSImage: Codable, Sendable, Hashable {
    public var id: String
    public var url: String
    public var mimeType: String
    public var width: Int?
    public var height: Int?
    public var alt: String
    public var title: String?
    /// Subtitles for a video, as a WebVTT address.
    public var subtitles: String?

    public init(id: String, url: String, mimeType: String, width: Int?, height: Int?, alt: String, title: String? = nil, subtitles: String? = nil) {
        self.id = id
        self.url = url
        self.mimeType = mimeType
        self.width = width
        self.height = height
        self.alt = alt
        self.title = title
        self.subtitles = subtitles
    }
}

/// A Link field. `href` already carries the target page's current address.
public struct CMSLink: Codable, Sendable, Hashable {
    /// `url`, `content`, `email` or `asset`.
    public var kind: String
    public var href: String?
    public var contentId: String?
    public var assetId: String?
    public var label: String?
    /// `_self`, `_blank` or `nil`.
    public var target: String?

    public init(kind: String, href: String?, contentId: String? = nil, assetId: String? = nil, label: String? = nil, target: String? = nil) {
        self.kind = kind
        self.href = href
        self.contentId = contentId
        self.assetId = assetId
        self.label = label
        self.target = target
    }
}

/// An entry a Reference field points at, delivered with `includeReferences`.
public struct CMSEntry<Fields: Decodable & Sendable>: Decodable, Sendable {
    public var id: String
    public var url: String?
    public var name: String
    public var contentType: String
    public var publishedAt: String?
    public var fields: Fields
}

extension CMSEntry: Encodable where Fields: Encodable {}
extension CMSEntry: Equatable where Fields: Equatable {}

/// A Reference field's value: an entry id, or the entry itself when read with `includeReferences`.
public indirect enum CMSReference<Fields: Decodable & Sendable>: Decodable, Sendable {
    case id(String)
    case entry(CMSEntry<Fields>)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let id = try? container.decode(String.self) {
            self = .id(id)
        } else {
            self = .entry(try container.decode(CMSEntry<Fields>.self))
        }
    }

    /// The entry id, either way.
    public var id: String {
        switch self {
        case .id(let id): return id
        case .entry(let entry): return entry.id
        }
    }

    /// The entry, when references were included.
    public var entry: CMSEntry<Fields>? {
        if case .entry(let entry) = self { return entry }
        return nil
    }
}

extension CMSReference: Encodable where Fields: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .id(let id): try container.encode(id)
        case .entry(let entry): try container.encode(entry)
        }
    }
}

extension CMSReference: Equatable where Fields: Equatable {}

/// Fields of one component type, such as a generated `HeroBlock`. See ``CMSComponent/decode(_:)``.
public protocol CMSBlockFields: Decodable, Sendable {
    /// The component's key, such as `hero`.
    static var blockType: String { get }
}

/// A block placed on a page: a component with its fields and the blocks in its slots.
public struct CMSComponent: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var type: String
    public var schemaVersion: Int
    public var fields: JSONValue
    /// The blocks in each slot, by slot name.
    public var children: [String: [CMSComponent]]
    public var variant: String?

    public init(id: String, type: String, schemaVersion: Int = 1, fields: JSONValue = [:], children: [String: [CMSComponent]] = [:], variant: String? = nil) {
        self.id = id
        self.type = type
        self.schemaVersion = schemaVersion
        self.fields = fields
        self.children = children
        self.variant = variant
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(String.self, forKey: .type)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        fields = try container.decodeIfPresent(JSONValue.self, forKey: .fields) ?? [:]
        children = try container.decodeIfPresent([String: [CMSComponent]].self, forKey: .children) ?? [:]
        variant = try container.decodeIfPresent(String.self, forKey: .variant)
    }

    /// Decodes the block's fields into your own type.
    public func fields<T: Decodable>(as type: T.Type) throws -> T {
        try fields.decode(T.self)
    }

    /// The block's fields as `T` when the block is of `T`'s type, otherwise `nil`.
    public func decode<T: CMSBlockFields>(_ type: T.Type) throws -> T? {
        guard self.type == T.blockType else { return nil }
        return try fields.decode(T.self)
    }
}

public struct CMSImageSummary: Codable, Sendable, Hashable {
    public var url: String
    public var width: Int?
    public var height: Int?
    public var alt: String
}

/// Ready-made metadata for a page.
public struct CMSSeo: Codable, Sendable, Hashable {
    public struct Robots: Codable, Sendable, Hashable {
        public var index: Bool
        public var follow: Bool
    }

    public struct OpenGraph: Codable, Sendable, Hashable {
        /// `website` or `article`.
        public var type: String
        public var title: String
        public var description: String
        public var url: String
        public var siteName: String
        public var locale: String
        public var image: CMSImageSummary?
    }

    public struct Twitter: Codable, Sendable, Hashable {
        public var card: String
        public var site: String?
        public var title: String
        public var description: String
        public var image: CMSImageSummary?
    }

    public struct Verification: Codable, Sendable, Hashable {
        public var google: String?
        public var bing: String?
    }

    public struct Alternate: Codable, Sendable, Hashable {
        public var hreflang: String
        public var href: String
    }

    public struct Breadcrumb: Codable, Sendable, Hashable {
        public var name: String
        public var url: String
    }

    public var title: String
    public var description: String
    public var canonical: String
    public var robots: Robots
    public var openGraph: OpenGraph?
    public var twitter: Twitter?
    public var verification: Verification
    public var alternates: [Alternate]
    public var breadcrumbs: [Breadcrumb]
    public var jsonLd: [JSONValue]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        canonical = try container.decodeIfPresent(String.self, forKey: .canonical) ?? ""
        robots = try container.decodeIfPresent(Robots.self, forKey: .robots) ?? Robots(index: true, follow: true)
        openGraph = try container.decodeIfPresent(OpenGraph.self, forKey: .openGraph)
        twitter = try container.decodeIfPresent(Twitter.self, forKey: .twitter)
        verification = try container.decodeIfPresent(Verification.self, forKey: .verification) ?? Verification(google: nil, bing: nil)
        alternates = try container.decodeIfPresent([Alternate].self, forKey: .alternates) ?? []
        breadcrumbs = try container.decodeIfPresent([Breadcrumb].self, forKey: .breadcrumbs) ?? []
        jsonLd = try container.decodeIfPresent([JSONValue].self, forKey: .jsonLd) ?? []
    }
}

/// What answered a page request, compared with what was asked for.
public struct CMSPageMeta: Sendable, Hashable {
    public var region: String
    public var locale: String
    public var requestedRegion: String
    public var requestedLocale: String
    /// `true` when another language answered.
    public var fallbackApplied: Bool
    /// `true` when another region answered.
    public var regionFallbackApplied: Bool
    public var draft: Bool
    /// `true` when the page was read with references included.
    public var references: Bool
}

/// A page, from ``CMSOrbitClient/page(_:options:)`` or ``CMSOrbitClient/resolve(_:referrer:options:)``.
public struct CMSPage: Codable, Sendable, Hashable {
    public struct Expired: Codable, Sendable, Hashable {
        public var message: String
    }

    public var url: String
    public var name: String
    public var contentType: String
    public var locale: String
    public var region: String
    public var requestedLocale: String
    public var requestedRegion: String
    public var fallbackApplied: Bool
    public var regionFallbackApplied: Bool
    public var draft: Bool
    public var publishedAt: String?
    public var version: Int
    public var fields: JSONValue
    public var components: [CMSComponent]
    public var seo: CMSSeo?
    /// Only on a campaign page past its end date that is set to stay visible.
    public var expired: Expired?
    /// The fallback details, gathered in one place.
    public internal(set) var meta: CMSPageMeta

    private enum CodingKeys: String, CodingKey {
        case url, name, contentType, locale, region, requestedLocale, requestedRegion, fallbackApplied
        case regionFallbackApplied, draft, publishedAt, version, fields, components, seo, expired
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decode(String.self, forKey: .url)
        name = try container.decode(String.self, forKey: .name)
        contentType = try container.decode(String.self, forKey: .contentType)
        locale = try container.decode(String.self, forKey: .locale)
        region = try container.decode(String.self, forKey: .region)
        requestedLocale = try container.decodeIfPresent(String.self, forKey: .requestedLocale) ?? locale
        requestedRegion = try container.decodeIfPresent(String.self, forKey: .requestedRegion) ?? region
        fallbackApplied = try container.decodeIfPresent(Bool.self, forKey: .fallbackApplied) ?? false
        regionFallbackApplied = try container.decodeIfPresent(Bool.self, forKey: .regionFallbackApplied) ?? false
        draft = try container.decodeIfPresent(Bool.self, forKey: .draft) ?? false
        publishedAt = try container.decodeIfPresent(String.self, forKey: .publishedAt)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 0
        fields = try container.decodeIfPresent(JSONValue.self, forKey: .fields) ?? [:]
        components = try container.decodeIfPresent([CMSComponent].self, forKey: .components) ?? []
        seo = try container.decodeIfPresent(CMSSeo.self, forKey: .seo)
        expired = try container.decodeIfPresent(Expired.self, forKey: .expired)
        meta = CMSPageMeta(
            region: region,
            locale: locale,
            requestedRegion: requestedRegion,
            requestedLocale: requestedLocale,
            fallbackApplied: fallbackApplied,
            regionFallbackApplied: regionFallbackApplied,
            draft: draft,
            references: false
        )
    }

    /// Decodes the page's fields into your own type, such as a generated `PageFields`.
    public func fields<T: Decodable>(as type: T.Type) throws -> T {
        try fields.decode(T.self)
    }
}

/// What an address is, from ``CMSOrbitClient/resolve(_:referrer:options:)``.
public enum CMSResolution: Sendable, Hashable {
    case page(CMSPage)
    case redirect(CMSRedirect)
    /// Published once and since removed, or a campaign page that has ended. Answer `410`.
    case gone
    /// Nothing was ever published here. Answer `404`.
    case notFound
}

public struct CMSRedirect: Sendable, Hashable {
    /// The address to send the visitor to.
    public var to: String
    /// The HTTP status to redirect with, such as `301`.
    public var status: Int
    /// `true` for `301` and `308`.
    public var permanent: Bool
    /// How many redirects were followed to reach `to`.
    public var hops: Int
}

public struct CMSNavItem: Codable, Sendable, Hashable {
    public var label: String
    public var href: String?
    public var target: String?
    public var icon: String?
    public var badge: String?
    public var description: String?
    public var children: [CMSNavItem]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decode(String.self, forKey: .label)
        href = try container.decodeIfPresent(String.self, forKey: .href)
        target = try container.decodeIfPresent(String.self, forKey: .target)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        badge = try container.decodeIfPresent(String.self, forKey: .badge)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        children = try container.decodeIfPresent([CMSNavItem].self, forKey: .children) ?? []
    }
}

/// A menu.
public struct CMSNavigation: Codable, Sendable, Hashable {
    public var key: String
    public var name: String
    public var items: [CMSNavItem]
}

/// A global entry, such as the footer.
public struct CMSGlobal: Codable, Sendable, Hashable {
    public var key: String
    public var name: String
    public var contentType: String
    /// The language that answered, which may be a fallback.
    public var locale: String
    public var fields: JSONValue
    public var components: [CMSComponent]

    public func fields<T: Decodable>(as type: T.Type) throws -> T {
        try fields.decode(T.self)
    }
}

/// One item of a list. `fields` is only present when the list was read with `.fields` or `.references`.
public struct CMSContentSummary<Fields: Decodable & Sendable>: Decodable, Sendable {
    public var id: String
    public var url: String?
    public var name: String
    public var contentType: String
    public var publishedAt: String?
    public var seo: JSONValue?
    public var fields: Fields?
}

extension CMSContentSummary: Encodable where Fields: Encodable {}
extension CMSContentSummary: Equatable where Fields: Equatable {}

public struct CMSContentList<Fields: Decodable & Sendable>: Decodable, Sendable {
    public var items: [CMSContentSummary<Fields>]
    public var total: Int
    public var page: Int
    public var hasMore: Bool
}

extension CMSContentList: Encodable where Fields: Encodable {}
extension CMSContentList: Equatable where Fields: Equatable {}

public struct CMSLocale: Codable, Sendable, Hashable {
    public var code: String
    public var name: String
    public var isDefault: Bool
}

public struct CMSRegion: Codable, Sendable, Hashable {
    public var key: String
    public var name: String
    public var locales: [CMSLocale]
}

public struct CMSTaxonomy: Codable, Sendable, Hashable {
    public struct Term: Codable, Sendable, Hashable {
        public var value: String
        public var label: String
        public var sortOrder: Int
    }

    public var key: String
    public var name: String
    public var terms: [Term]
}

public struct CMSSitemapIndex: Codable, Sendable, Hashable {
    public struct Sitemap: Codable, Sendable, Hashable {
        public var region: String
        public var locale: String
        public var base: String?
        public var pages: Int
        public var files: Int
    }

    public var indexable: Bool
    public var sitemaps: [Sitemap]
}

public struct CMSSitemapEntry: Codable, Sendable, Hashable {
    public struct Image: Codable, Sendable, Hashable {
        public var loc: String
        public var title: String?
    }

    public var loc: String
    public var lastmod: String?
    public var changefreq: String?
    public var priority: Double?
    public var images: [Image]
    public var alternates: [CMSSeo.Alternate]
}

public struct CMSSitemap: Codable, Sendable, Hashable {
    public var region: String
    public var locale: String
    public var page: Int
    public var totalPages: Int
    public var entries: [CMSSitemapEntry]
}

public struct CMSRobots: Codable, Sendable, Hashable {
    public var indexable: Bool
    public var content: String
}

public struct CMSSchemaField: Codable, Sendable, Hashable {
    public struct Option: Codable, Sendable, Hashable {
        public var label: String
        public var value: String
    }

    public var key: String
    public var name: String
    public var type: String
    public var required: Bool
    public var description: String?
    public var options: [Option]?
    public var allowedComponents: [String]?
    public var allowedContentTypes: [String]?
    public var taxonomy: String?
    public var validation: JSONValue?
    /// `{ field, equals }` when the field is only delivered while another field holds a value.
    public var showWhen: JSONValue?
}

public struct CMSSchema: Codable, Sendable, Hashable {
    public struct ContentType: Codable, Sendable, Hashable {
        public var key: String
        public var name: String
        public var description: String?
        public var isGlobal: Bool
        public var fields: [CMSSchemaField]
    }

    public struct Component: Codable, Sendable, Hashable {
        public var key: String
        public var name: String
        public var description: String?
        public var group: String?
        /// A list of component keys, or `"*"` for any.
        public var allowedChildren: JSONValue
        public var fields: [CMSSchemaField]
    }

    public var contentTypes: [ContentType]
    public var components: [Component]
}

/// Banners or popups, with the CMS clock so countdowns tick from the server's time.
public struct CMSTimed<Item: Decodable & Sendable>: Decodable, Sendable {
    public var serverTime: String
    public var items: [Item]
}

extension CMSTimed: Encodable where Item: Encodable {}
extension CMSTimed: Equatable where Item: Equatable {}

public struct CMSSegment: Codable, Sendable, Hashable {
    public var text: String
    public var highlight: Bool
}

public struct CMSCountdown: Codable, Sendable, Hashable {
    public struct FollowUp: Codable, Sendable, Hashable {
        public var text: String
        public var link: CMSLink?
    }

    public var label: String?
    public var startsAt: String?
    public var endsAt: String?
    public var timeZone: String
    public var style: String
    public var icon: String?
    public var button: CMSLink?
    /// `upcoming`, `running` or `ended`.
    public var status: String
    /// `countdown`, `hidden`, `followUp` or `ended`.
    public var display: String
    public var followUp: FollowUp?
    public var endedText: String?
}

/// One block of a banner or popup.
public enum CMSCampaignBlock: Codable, Sendable, Hashable {
    case image(id: String, image: CMSImage?)
    /// `size` is `large`, `medium` or `eyebrow`.
    case heading(id: String, text: String, size: String)
    case text(id: String, body: CMSRichText)
    case message(id: String, text: String, segments: [CMSSegment])
    /// `style` is `primary`, `secondary` or `link`.
    case button(id: String, text: String, link: CMSLink?, style: String)
    case promoCode(id: String, code: String, label: String?)
    case terms(id: String, text: String)
    case form(id: String, form: String, submitText: String?)
    case countdown(id: String, countdown: CMSCountdown)
    /// A block type this version of the SDK does not know yet.
    case unknown(id: String, type: String, value: JSONValue)

    private enum CodingKeys: String, CodingKey {
        case id, type, image, text, size, body, segments, link, style, code, label, form, submitText, countdown
    }

    public var id: String {
        switch self {
        case .image(let id, _), .heading(let id, _, _), .text(let id, _), .message(let id, _, _),
             .button(let id, _, _, _), .promoCode(let id, _, _), .terms(let id, _), .form(let id, _, _),
             .countdown(let id, _), .unknown(let id, _, _):
            return id
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(String.self, forKey: .id)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "image":
            self = .image(id: id, image: try c.decodeIfPresent(CMSImage.self, forKey: .image))
        case "heading":
            self = .heading(id: id, text: try c.decode(String.self, forKey: .text), size: try c.decodeIfPresent(String.self, forKey: .size) ?? "medium")
        case "text":
            self = .text(id: id, body: try c.decode(String.self, forKey: .body))
        case "message":
            self = .message(id: id, text: try c.decode(String.self, forKey: .text), segments: try c.decodeIfPresent([CMSSegment].self, forKey: .segments) ?? [])
        case "button":
            self = .button(
                id: id,
                text: try c.decode(String.self, forKey: .text),
                link: try c.decodeIfPresent(CMSLink.self, forKey: .link),
                style: try c.decodeIfPresent(String.self, forKey: .style) ?? "primary"
            )
        case "promoCode":
            self = .promoCode(id: id, code: try c.decode(String.self, forKey: .code), label: try c.decodeIfPresent(String.self, forKey: .label))
        case "terms":
            self = .terms(id: id, text: try c.decode(String.self, forKey: .text))
        case "form":
            self = .form(id: id, form: try c.decode(String.self, forKey: .form), submitText: try c.decodeIfPresent(String.self, forKey: .submitText))
        case "countdown":
            self = .countdown(id: id, countdown: try c.decode(CMSCountdown.self, forKey: .countdown))
        default:
            self = .unknown(id: id, type: type, value: try JSONValue(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        if case .unknown(_, _, let value) = self {
            try value.encode(to: encoder)
            return
        }
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        switch self {
        case .image(_, let image):
            try c.encode("image", forKey: .type)
            try c.encode(image, forKey: .image)
        case .heading(_, let text, let size):
            try c.encode("heading", forKey: .type)
            try c.encode(text, forKey: .text)
            try c.encode(size, forKey: .size)
        case .text(_, let body):
            try c.encode("text", forKey: .type)
            try c.encode(body, forKey: .body)
        case .message(_, let text, let segments):
            try c.encode("message", forKey: .type)
            try c.encode(text, forKey: .text)
            try c.encode(segments, forKey: .segments)
        case .button(_, let text, let link, let style):
            try c.encode("button", forKey: .type)
            try c.encode(text, forKey: .text)
            try c.encode(link, forKey: .link)
            try c.encode(style, forKey: .style)
        case .promoCode(_, let code, let label):
            try c.encode("promoCode", forKey: .type)
            try c.encode(code, forKey: .code)
            try c.encode(label, forKey: .label)
        case .terms(_, let text):
            try c.encode("terms", forKey: .type)
            try c.encode(text, forKey: .text)
        case .form(_, let form, let submitText):
            try c.encode("form", forKey: .type)
            try c.encode(form, forKey: .form)
            try c.encode(submitText, forKey: .submitText)
        case .countdown(_, let countdown):
            try c.encode("countdown", forKey: .type)
            try c.encode(countdown, forKey: .countdown)
        case .unknown:
            break
        }
    }
}

public struct CMSPopup: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    /// `sideBySide`, `stacked` or `text`.
    public var layout: String
    /// `light`, `dark` or `brand`.
    public var style: String
    public var minimisedText: String?
    public var blocks: [CMSCampaignBlock]
    public var priority: Int
    public var hideForDays: Int
    public var maxViews: Int?
    public var trackingLabel: String?
    public var startsAt: String?
    public var endsAt: String?
}

public struct CMSBanner: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var blocks: [CMSCampaignBlock]
    /// The message as plain text.
    public var text: String
    public var segments: [CMSSegment]
    public var link: CMSLink?
    public var background: String
    /// The text colour chosen by the editor, or white or dark, whichever reads best on `background`.
    public var foreground: String
    /// `aboveHeader` or `belowHeader`.
    public var placement: String
    /// The pages it targets, with `/*` for a whole section. Empty for every page.
    public var paths: [String]
    public var pinned: Bool
    public var priority: Int
    public var trackingLabel: String?
    public var countdown: CMSCountdown?
    /// Only set on ``next``: when that banner takes over.
    public var startsAt: String?
    public var endsAt: String?
    private var _next: Indirect<CMSBanner>?

    /// The banner that takes over when this one ends.
    public var next: CMSBanner? {
        get { _next?.value }
        set { _next = newValue.map(Indirect.init) }
    }

    private enum CodingKeys: String, CodingKey {
        case id, blocks, text, segments, link, background, foreground, placement, paths, pinned, priority
        case trackingLabel, countdown, startsAt, endsAt
        case _next = "next"
    }
}

final class Indirect<Value: Sendable & Hashable & Codable>: Sendable, Hashable, Codable {
    let value: Value

    init(_ value: Value) { self.value = value }

    required init(from decoder: Decoder) throws {
        value = try Value(from: decoder)
    }

    func encode(to encoder: Encoder) throws {
        try value.encode(to: encoder)
    }

    static func == (lhs: Indirect, rhs: Indirect) -> Bool { lhs.value == rhs.value }

    func hash(into hasher: inout Hasher) { hasher.combine(value) }
}

public struct CMSProduct: Codable, Sendable, Hashable {
    public struct Filter: Codable, Sendable, Hashable {
        public var taxonomy: String?
        public var value: String
        public var label: String
    }

    public var slug: String
    public var url: String?
    public var name: String
    public var phorestId: String?
    public var size: String?
    /// `nil` when the product is not linked to the shop catalogue.
    public var price: Double?
    public var currency: String?
    public var wasPrice: Double?
    public var inStock: Bool?
    public var onSale: Bool
    public var badges: [String]
    public var benefits: CMSRichText?
    public var directions: CMSRichText?
    public var ingredients: CMSRichText?
    public var terms: String?
    public var images: [CMSImageSummary]
    public var filters: [Filter]
    public var relatedSlugs: [String]
    public var seo: CMSSeo?
    public var publishedAt: String?
}

public struct CMSProductPage: Codable, Sendable, Hashable {
    public var items: [CMSProduct]
    public var total: Int
    public var page: Int
    public var hasMore: Bool
}

/// What a preview token from the CMS editor is for, from ``CMSOrbitClient/verifyPreview(token:)``.
public struct CMSPreviewSession: Codable, Sendable, Hashable {
    /// The entry's id.
    public var id: String
    public var name: String
    /// The page's address, or `nil` for an entry without one.
    public var url: String?
    public var contentTypeKey: String
    public var status: String
    /// The editor's saved draft, as stored by the CMS: image ids rather than images, and references as ids.
    public var draft: JSONValue
}
