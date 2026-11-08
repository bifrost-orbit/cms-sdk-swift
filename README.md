# CMS Orbit for Swift

The official Swift SDK for the CMS Orbit delivery API. Read pages, menus, site-wide content, lists, banners, popups and products from CMS Orbit in iOS, iPadOS, macOS, tvOS and watchOS apps, and in server-side Swift.

- async/await on `URLSession`, no dependencies
- Safe under Swift 6 strict concurrency: the client and every model are `Sendable`
- `Codable` models for every answer, with a `JSONValue` for fields you have not typed yet
- Decode fields and pages into your own types
- Retries, timeouts and typed errors, matching the JavaScript SDK

It needs Swift 5.9 or later, and iOS 15, macOS 12, tvOS 15 or watchOS 8 or later.

Full documentation: [docs.bifrostorbit.com/cms/developers/sdk-swift](https://docs.bifrostorbit.com/cms/developers/sdk-swift/). The delivery API itself is described in [Delivery API](https://docs.bifrostorbit.com/cms/developers/delivery-api/).

## Install

Swift Package Manager reads packages from the root of a Git repository, so the SDK is published from its own repository.

In Xcode, choose **File › Add Package Dependencies…** and enter:

```
https://github.com/bifrost-orbit/cms-sdk-swift
```

In `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/bifrost-orbit/cms-sdk-swift", from: "0.2.0"),
],
targets: [
    .target(name: "App", dependencies: [.product(name: "CMSOrbit", package: "cms-sdk-swift")]),
]
```

## Quick start

Create a public key in **Configuration › API keys**. It starts with `cms_pk_` and reads published content only, so it is safe to ship in an app.

```swift
import CMSOrbit

let cms = try CMSOrbitClient(
    apiKey: "cms_pk_...",
    region: "germany",
    locale: "de-DE"
)

let page = try await cms.page("/gear/fjell-gtx-boot")
print(page.name, page.fields["title"]?.stringValue ?? "")
```

| Option | What it does |
| --- | --- |
| `apiKey` | A public key, `cms_pk_…`. Required. A secret `cms_sk_…` key is refused with `CMSOrbitError.secretKeyNotAllowed`, because anything in an app can be read by whoever installs it. |
| `environment` | `.production` (`https://api.bifrostorbit.com/cms`, the default), `.staging` (`https://api-stage.bifrostorbit.com/cms`) or `.custom(url)`. Use a key from the same environment. |
| `baseURL` | Overrides the environment's address. |
| `region` | Used when a call names no region, such as `germany` or `de`. |
| `locale` | Used when a call names no language, such as `de-DE`. Without it, the region's default language answers. |
| `previewKey` | A secret key for drafts. Server-side Swift only: refused on iOS, tvOS, watchOS and visionOS. See [Preview](#preview). |
| `timeout` | Seconds per attempt. 5 by default. |
| `retries` | Extra attempts after a connection failure or a `5xx` answer. 2 by default, waiting 0.25, 0.75 and 2 seconds. |
| `session` | Your own `URLSession`, for a custom cache, proxies or tests. |

Create one client and share it: it is `Sendable` and holds no mutable state.

## Every method

Each call takes `CMSRequestOptions` where it makes sense: `region`, `locale`, `strict` (refuse every fallback), `includeReferences` (replace Reference fields' ids with the entries) and `preview`. Anything left out uses the client's defaults.

| Method | Endpoint | Returns |
| --- | --- | --- |
| `resolve(_ path:, referrer:, options:)` | `GET /resolve` | `CMSResolution`: `.page`, `.redirect`, `.gone` or `.notFound` |
| `page(_ path:, options:)` | `GET /content` | `CMSPage`, or throws `.notFound` |
| `findPage(_ path:, options:)` | `GET /content` | `CMSPage?` |
| `content(_ type:, path:, options:)` | `GET /content` | The page decoded into your own type |
| `navigation(_ key:, options:)` / `findNavigation` | `GET /navigation` | `CMSNavigation` |
| `global(_ key:, options:)` / `findGlobal` | `GET /global` | `CMSGlobal` |
| `global(_ type:, key:, options:)` | `GET /global` | The entry decoded into your own type |
| `list(_ options:)` | `GET /list` | `CMSContentList<JSONValue>` |
| `list(_ options:, fields:)` | `GET /list` | `CMSContentList<YourFields>` |
| `regions()` | `GET /regions` | `[CMSRegion]` |
| `locales(region:)` | `GET /regions` | `[CMSLocale]` of one region, or of all |
| `taxonomy(_ key:, locale:)` | `GET /taxonomies/{key}` | `CMSTaxonomy` |
| `banners(.path(_) or .everyPage, loggedIn:, options:)` | `GET /banners` | `CMSTimed<CMSBanner>` |
| `popups(path:, loggedIn:, options:)` | `GET /popups` | `CMSTimed<CMSPopup>` |
| `products(page:, perPage:, filter:, options:)` | `GET /products` | `CMSProductPage` |
| `sitemapIndex()` | `GET /sitemap` | `CMSSitemapIndex` |
| `sitemap(region:, locale:, page:)` | `GET /sitemap?region=` | `CMSSitemap` |
| `robots()` | `GET /robots` | `CMSRobots` |
| `schema()` | `GET /schema` | `CMSSchema` |
| `graphql(_ query:, variables:, operationName:, preview:, as:)` | `POST /graphql` | Your own type |
| `verifyPreview(token:)` | `GET /preview` | `CMSPreviewSession` |
| `get(_ type:, path:, query:, preview:)` | Any | Your own type, for endpoints the SDK does not cover yet |

### Pages and redirects

Call `resolve` before showing an address, so redirects and removed pages behave:

```swift
switch try await cms.resolve("/offers/winter") {
case .page(let page):
    show(page)
case .redirect(let redirect):
    open(redirect.to)
case .gone, .notFound:
    showNotFound()
}
```

`page.meta` says what answered compared with what was asked for. When `page.meta.fallbackApplied` is `true`, another language answered, so you can show "This page is not available in English yet."

### Menus and site-wide content

```swift
let menu = try await cms.navigation("main")
for item in menu.items {
    print(item.label, item.href ?? "", item.children.count)
}

let footer = try await cms.global("footer")
```

### Lists

```swift
let products = try await cms.list(CMSListOptions(
    type: "product",
    include: [.fields],
    perPage: 20,
    filter: ["activity": "hiking"],
    sort: .publishedAtDescending
))
```

Ask for the next page while `hasMore` is `true`.

### Banners, popups and products

```swift
let banners = try await cms.banners(.path("/trips"), loggedIn: false)
for banner in banners.items {
    for block in banner.blocks {
        switch block {
        case .message(_, let text, _): print(text)
        case .button(_, let text, let link, _): print(text, link?.href ?? "")
        case .countdown(_, let countdown): print(countdown.endsAt ?? "")
        default: break
        }
    }
}

let products = try await cms.products(perPage: 24, filter: "hiking")
```

`serverTime` is the CMS clock, so countdowns can tick from it rather than the device's clock.

## Decoding your own types

Fields arrive as `JSONValue`, which you can read straight away:

```swift
let title = page.fields["title"]?.stringValue
let image = page.fields["heroImage"]
```

For type safety, write `Decodable` structs and decode into them. The SDK's models, such as `CMSImage`, `CMSLink`, `CMSComponent` and `CMSReference`, decode inside your types.

```swift
struct PageFields: Decodable, Sendable {
    var title: String
    var heroImage: CMSImage?
}

let fields = try page.fields(as: PageFields.self)
```

Or decode the whole answer:

```swift
struct ArticlePage: Decodable {
    struct Fields: Decodable { var title: String; var body: CMSRichText }
    var name: String
    var fields: Fields
}

let article = try await cms.content(ArticlePage.self, path: "/journal/winter-hiking")
```

Lists take a fields type too:

```swift
struct FaqEntry: Decodable, Sendable {
    var question: String
    var answer: CMSRichText
}

let faqs = try await cms.list(CMSListOptions(type: "faqEntry", include: [.fields]), fields: FaqEntry.self)
```

Reference fields hold entry ids. Read with `includeReferences: true` and type them as `CMSReference<Fields>`, which is either `.id` or `.entry`:

```swift
struct FaqList: CMSBlockFields {
    static let blockType = "faqList"
    var heading: String
    var questions: [CMSReference<FaqEntry>]
}
```

## Rendering blocks in SwiftUI

A page's body is `page.components`, a list of `CMSComponent`: `id`, `type`, `fields`, `children` (blocks in each slot) and `variant`. Give each component type a struct conforming to `CMSBlockFields`, and decode with `component.decode(_:)`, which returns `nil` for other types:

```swift
struct HeroBlock: CMSBlockFields {
    static let blockType = "hero"
    var heading: String
    var image: CMSImage?
    var link: CMSLink?
}

struct CardGridBlock: CMSBlockFields {
    static let blockType = "card-grid"
    var title: String?
}
```

A small renderer switches on the type, and draws nothing for types it does not know yet, so a new component in the CMS never breaks the app:

```swift
import SwiftUI
import CMSOrbit

struct BlockView: View {
    let block: CMSComponent

    var body: some View {
        if let hero = try? block.decode(HeroBlock.self) {
            HeroView(hero: hero)
        } else if let grid = try? block.decode(CardGridBlock.self) {
            CardGridView(grid: grid, cards: block.children["cards"] ?? [])
        } else {
            EmptyView()
        }
    }
}

struct PageView: View {
    let page: CMSPage

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                ForEach(page.components) { BlockView(block: $0) }
            }
        }
        .navigationTitle(page.name)
    }
}

struct HeroView: View {
    let hero: HeroBlock

    var body: some View {
        VStack(alignment: .leading) {
            AsyncImage(url: hero.image?.url(width: 1280)) { $0.resizable().scaledToFill() } placeholder: { Color.secondary }
                .frame(height: 240)
                .clipped()
                .accessibilityLabel(hero.image?.alt ?? "")
            Text(hero.heading).font(.largeTitle.bold())
        }
    }
}
```

If you prefer a registry, the same pattern works as a protocol:

```swift
protocol BlockRenderer {
    associatedtype Fields: CMSBlockFields
    associatedtype Body: View
    @ViewBuilder func render(_ fields: Fields, block: CMSComponent) -> Body
}
```

Blocks in a slot arrive both in `block.children[slot]` and on the slot's field. Rich text arrives as HTML; render it with `AttributedString` or a web view. `image.url(width:)` asks the CMS for a resized copy of uploaded images.

## Insights Orbit

Pages carry `id`, the entry's id, and `insights`, a `CMSInsightsSite` when the space is connected to Insights Orbit, both `nil` otherwise. In server-side Swift, `CMSInsights.tags(page:)` writes the script with the site key and `<meta name="insights-content">` with the entry's id, or an empty string without a site key:

```swift
let head = CMSInsights.tags(page: page, src: "/stats/script.js", api: "/stats/collect")
```

It takes `site`, `contentId`, `src`, `api`, `disable`, `campaigns` and `waitForConsent`, like `CmsInsights` in the JavaScript SDK.

## Preview

Editors preview drafts in the CMS editor, which opens your website with `?preview=<token>`. An app can take part in two ways.

**Check a preview link.** If a preview link opens your app, for example as a universal link, read the token and ask the CMS which entry it is for. This needs no secret key:

```swift
if let token = CMSOrbitClient.previewToken(from: url) {
    let session = try await cms.verifyPreview(token: token)
    print(session.name, session.url ?? "", session.draft)
}
```

Tokens last an hour. An invalid or expired token throws `.unauthorized`. `session.draft` is the editor's saved draft as the CMS stores it, with image ids rather than images.

**Read drafts from a server.** Reading drafts through the delivery API needs a secret key, which must never be in an app. In server-side Swift, on macOS or Linux, give the client a `previewKey` and pass `preview: true`:

```swift
let cms = try CMSOrbitClient(
    apiKey: Environment.get("CMS_PUBLIC_KEY")!,
    environment: .staging,
    previewKey: Environment.get("CMS_PREVIEW_KEY")
)
let draft = try await cms.page("/gear/fjell-gtx-boot", options: .init(preview: true))
```

Secret keys only exist for staging environments, and drafts are never cached. An app that needs to show drafts should ask your own server, which holds the key.

## Webhooks

[Publish webhooks](https://docs.bifrostorbit.com/cms/developers/webhooks/) are signed. On a Swift server, `CMSWebhook.parse` checks the signature and the timestamp and answers the message, or `nil` when it is not genuine or is more than five minutes old. Pass the raw body, before any JSON parsing. With Vapor:

```swift
app.post("api", "cms-webhook") { req async -> HTTPStatus in
    guard let message = CMSWebhook.parse(
        secret: Environment.get("CMS_WEBHOOK_SECRET")!,
        timestamp: req.headers.first(name: CMSWebhook.timestampHeader) ?? "",
        signature: req.headers.first(name: CMSWebhook.signatureHeader) ?? "",
        body: req.body.string ?? ""
    ) else { return .unauthorized }
    if message.event != "webhook.test" {
        await pageCache.clear()
    }
    return .noContent
}
```

`CMSWebhook.verify(secret:timestamp:signature:body:)` answers only `true` or `false`. Both take the body as `Data` or `String`, and use the whole secret, including `whsec_`. An empty secret never verifies.

`CMSWebhook` uses CryptoKit, so it is there on Apple platforms (macOS, iOS, tvOS and watchOS) and not on Linux, where the rest of the SDK still builds. On a Linux server, check the signature with [swift-crypto](https://github.com/apple/swift-crypto) as [Receive it without the SDK](https://docs.bifrostorbit.com/cms/developers/webhooks/#receive-it-without-the-sdk) describes.

## Errors

Everything throws `CMSOrbitError`, apart from `CancellationError` when the calling task is cancelled.

| Case | When |
| --- | --- |
| `.notFound(message:)` | `404`: nothing at the address, or no menu, global entry, taxonomy, region or language with that key |
| `.unauthorized(message:)` | `401`: the key was refused or has expired, or may not read that region or language |
| `.subscriptionInactive` | `402`: the organisation's CMS Orbit trial or plan has ended, so delivery is paused. Not retried |
| `.rateLimited(retryAfter:message:)` | `429`: wait `retryAfter` seconds |
| `.http(status:code:message:)` | Any other `4xx`, such as `400 bad_request` for an unknown sort |
| `.server(status:message:)` | `5xx`, after the retries |
| `.unavailable(message:)` | The CMS could not be reached or did not answer in time, after the retries |
| `.decoding(_:)` | The answer did not match the type asked for |
| `.graphQL(code:message:)` | A GraphQL answer carried errors |
| `.invalidAPIKey`, `.secretKeyNotAllowed`, `.previewKeyRequired`, `.invalidURL` | The client was set up wrongly |

```swift
do {
    let page = try await cms.page(path)
    show(page)
} catch CMSOrbitError.notFound {
    showNotFound()
} catch CMSOrbitError.rateLimited(let retryAfter, _) {
    try await Task.sleep(nanoseconds: UInt64(retryAfter * 1_000_000_000))
}
```

`findPage`, `findNavigation` and `findGlobal` return `nil` instead of throwing `.notFound`.

When your organisation's CMS Orbit trial or plan has ended, delivery is paused: every call throws `.subscriptionInactive` (status `402`, code `subscription_inactive`) straight away, without retrying, whatever code the API sends. Check `error.isSubscriptionInactive`, keep showing what the app already has on disk, and show a calm "temporarily unavailable" message where there is nothing. Nothing is deleted, and content comes back as soon as an owner chooses a plan.

## Caching

The client does not keep answers itself. Published answers carry `Cache-Control` with `s-maxage`, which is meant for shared caches such as a CDN, so `URLSession`'s own cache should not be relied on to keep them. Keep what the app shows in memory or on disk, show it straight away on the next launch, and read it again when the app returns to the foreground. Drafts are always read fresh. See Caching in the [delivery API](https://docs.bifrostorbit.com/cms/developers/delivery-api/).

## Testing your app

Pass a `URLSession` whose configuration has your own `URLProtocol` in `protocolClasses`, and answer requests with JSON shaped like the [delivery API](https://docs.bifrostorbit.com/cms/developers/delivery-api/), so tests and SwiftUI previews run without the network.

## Licence

MIT
