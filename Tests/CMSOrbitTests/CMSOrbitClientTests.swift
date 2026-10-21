import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import CMSOrbit

final class CMSOrbitClientTests: XCTestCase {
    private let publicKey = "cms_pk_test_public"

    private func client(
        region: String? = "ireland",
        locale: String? = nil,
        baseURL: URL? = URL(string: "https://api.example.com/cms"),
        previewKey: String? = nil,
        retries: Int = 0,
        _ responses: StubResponse...
    ) throws -> CMSOrbitClient {
        StubProtocol.reset(responses)
        return try CMSOrbitClient(
            apiKey: publicKey,
            baseURL: baseURL,
            region: region,
            locale: locale,
            previewKey: previewKey,
            retries: retries,
            session: StubProtocol.session()
        )
    }

    // MARK: - Keys and addresses

    func testRefusesSecretKeys() {
        XCTAssertThrowsError(try CMSOrbitClient(apiKey: "cms_sk_secret")) { error in
            XCTAssertEqual(error as? CMSOrbitError, .secretKeyNotAllowed)
            XCTAssertTrue(error.localizedDescription.contains("cms_pk_"))
        }
    }

    func testRefusesMissingAndUnknownKeys() {
        XCTAssertThrowsError(try CMSOrbitClient(apiKey: "")) { error in
            guard case .invalidAPIKey = error as? CMSOrbitError else { return XCTFail("\(error)") }
        }
        XCTAssertThrowsError(try CMSOrbitClient(apiKey: "cms_mt_token")) { error in
            guard case .invalidAPIKey = error as? CMSOrbitError else { return XCTFail("\(error)") }
        }
    }

    func testPreviewKeyMustBeSecret() {
        XCTAssertThrowsError(try CMSOrbitClient(apiKey: publicKey, previewKey: "cms_pk_other")) { error in
            guard case .invalidAPIKey = error as? CMSOrbitError else { return XCTFail("\(error)") }
        }
        XCTAssertNoThrow(try CMSOrbitClient(apiKey: publicKey, previewKey: "cms_sk_preview"))
    }

    func testBuildsTheApiAddressLikeTheJavaScriptSdk() throws {
        XCTAssertEqual(CMSOrbitClient.apiBase("https://api.example.com/cms"), "https://api.example.com/cms/api/cdn/v1")
        XCTAssertEqual(CMSOrbitClient.apiBase("https://api.example.com/cms/"), "https://api.example.com/cms/api/cdn/v1")
        XCTAssertEqual(CMSOrbitClient.apiBase("https://api.example.com/cms/api/cdn"), "https://api.example.com/cms/api/cdn/v1")
        XCTAssertEqual(CMSOrbitClient.apiBase("https://api.example.com/cms/api/cdn/v2"), "https://api.example.com/cms/api/cdn/v2")

        let production = try CMSOrbitClient(apiKey: publicKey)
        XCTAssertEqual(production.apiURL.absoluteString, "https://api.bifrostorbit.com/cms/api/cdn/v1")
        XCTAssertEqual(production.origin.absoluteString, "https://api.bifrostorbit.com/cms")

        let staging = try CMSOrbitClient(apiKey: publicKey, environment: .staging)
        XCTAssertEqual(staging.apiURL.absoluteString, "https://api-stage.bifrostorbit.com/cms/api/cdn/v1")
    }

    // MARK: - Requests

    func testPageSendsKeyRegionAndPath() async throws {
        let cms = try client(locale: "en-IE", .fixture("page"))
        let page = try await cms.page("/services/consultations", options: .init(strict: true, includeReferences: true))

        let request = try XCTUnwrap(StubProtocol.requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.path, "/cms/api/cdn/v1/content")
        XCTAssertEqual(request.queryItems, [
            "url": "/services/consultations",
            "region": "ireland",
            "locale": "en-IE",
            "strict": "true",
            "include": "references",
        ])
        XCTAssertTrue(request.url!.absoluteString.contains("url=%2Fservices%2Fconsultations"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(publicKey)")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(page.meta.references, true)
    }

    func testOptionsOverrideClientDefaultsAndEmptyValuesAreLeftOut() async throws {
        let cms = try client(.json(#"{"data":{"key":"main","name":"Main menu","items":[]}}"#))
        _ = try await cms.navigation("main", options: .init(region: "uk", locale: "en-GB"))
        XCTAssertEqual(StubProtocol.requests.first?.queryItems, ["key": "main", "region": "uk", "locale": "en-GB"])

        let bare = try client(region: nil, .json(#"{"data":{"key":"main","name":"Main menu","items":[]}}"#))
        _ = try await bare.navigation("main")
        XCTAssertEqual(StubProtocol.requests.first?.queryItems, ["key": "main"])
    }

    func testListSendsFiltersIncludesAndSort() async throws {
        let body = #"""
        {"data":{"items":[{"id":"66f1","url":null,"name":"Can I cancel?","contentType":"faqEntry","publishedAt":null,"seo":null,"fields":{"question":"Can I cancel?","answer":"<p>Yes.</p>","category":"pricing"}}],"total":1,"page":1,"hasMore":false}}
        """#
        let cms = try client(.json(body), .json(body))
        let options = CMSListOptions(
            type: "faqEntry",
            include: [.references, .fields],
            page: 2,
            perPage: 10,
            filter: ["duration": "60", "category": "pricing"],
            tag: "new",
            sort: .publishedAtDescending,
            query: "cancel"
        )
        let list = try await cms.list(options)

        let request = try XCTUnwrap(StubProtocol.requests.first)
        XCTAssertEqual(request.path, "/cms/api/cdn/v1/list")
        XCTAssertEqual(request.queryItems, [
            "type": "faqEntry",
            "region": "ireland",
            "page": "2",
            "perPage": "10",
            "tag": "new",
            "sort": "-publishedAt",
            "q": "cancel",
            "include": "fields,references",
            "filter[category]": "pricing",
            "filter[duration]": "60",
        ])
        XCTAssertTrue(request.url!.absoluteString.contains("filter%5Bcategory%5D=pricing"))
        XCTAssertEqual(list.items.first?.fields?["question"]?.stringValue, "Can I cancel?")

        struct Faq: Decodable, Sendable {
            let question: String
            let answer: String
        }
        let typed = try await cms.list(CMSListOptions(type: "faqEntry", include: [.fields]), fields: Faq.self)
        XCTAssertEqual(typed.items.first?.fields?.answer, "<p>Yes.</p>")
        XCTAssertEqual(typed.total, 1)
    }

    func testResolveHandlesEveryKind() async throws {
        let cms = try client(
            .json(#"{"data":{"kind":"redirect","destination":"/services/consultations","statusCode":308,"hops":2}}"#),
            .json(#"{"data":{"kind":"gone"}}"#, status: 410),
            .json(#"{"data":{"kind":"notFound"}}"#, status: 404),
            .json(#"{"data":{"kind":"page","page":{"url":"/","name":"Home","contentType":"page","locale":"en-IE","region":"ireland","draft":false,"publishedAt":null,"version":1,"fields":{},"components":[],"seo":{"title":"Home"}}}}"#)
        )

        let redirect = try await cms.resolve("/consultations", referrer: "https://www.example.com/old")
        XCTAssertEqual(redirect, .redirect(CMSRedirect(to: "/services/consultations", status: 308, permanent: true, hops: 2)))
        XCTAssertEqual(StubProtocol.requests.first?.value(forHTTPHeaderField: "x-cms-referrer"), "https://www.example.com/old")
        XCTAssertEqual(StubProtocol.requests.first?.path, "/cms/api/cdn/v1/resolve")

        let gone = try await cms.resolve("/old-offer")
        XCTAssertEqual(gone, .gone)
        let notFound = try await cms.resolve("/missing")
        XCTAssertEqual(notFound, .notFound)

        guard case .page(let page) = try await cms.resolve("/") else { return XCTFail("Expected a page") }
        XCTAssertEqual(page.requestedRegion, "ireland")
        XCTAssertEqual(page.meta.regionFallbackApplied, false)
        XCTAssertEqual(page.seo?.title, "Home")
        XCTAssertEqual(page.seo?.robots.index, true)
    }

    func testEndpointsUseTheRightPathsAndParameters() async throws {
        let timed = #"{"data":{"serverTime":"2026-10-17T10:00:00.000Z","items":[]}}"#
        let cms = try client(
            .json(timed),
            .json(timed),
            .json(timed),
            .json(#"{"data":{"items":[],"total":0,"page":1,"hasMore":false}}"#),
            .json(#"{"data":{"key":"skin-concern","name":"Skin concern","terms":[{"value":"acne","label":"Acne","sortOrder":0}]}}"#),
            .json(#"{"data":{"indexable":true,"sitemaps":[]}}"#),
            .json(#"{"data":{"region":"ireland","locale":"en-IE","page":2,"totalPages":2,"entries":[]}}"#),
            .json(#"{"data":{"indexable":false,"content":"User-agent: *\nDisallow: /\n"}}"#),
            .json(#"{"data":{"contentTypes":[],"components":[{"key":"hero","name":"Hero","description":null,"group":null,"allowedChildren":"*","fields":[]}]}}"#),
            .json(#"{"data":{"key":"footer","name":"Footer","contentType":"footer","locale":"en-IE","fields":{"copyright":"© Acme Clinic"},"components":[]}}"#)
        )

        _ = try await cms.banners(.path("/services"), loggedIn: true)
        _ = try await cms.banners(.everyPage)
        _ = try await cms.popups(path: "/")
        _ = try await cms.products(page: 2, perPage: 12, filter: "acne")
        let taxonomy = try await cms.taxonomy("skin-concern", locale: "ga-IE")
        _ = try await cms.sitemapIndex()
        _ = try await cms.sitemap(page: 2)
        let robots = try await cms.robots()
        let schema = try await cms.schema()
        let footer = try await cms.global("footer")

        let requests = StubProtocol.requests
        XCTAssertEqual(requests.map(\.path), [
            "/cms/api/cdn/v1/banners",
            "/cms/api/cdn/v1/banners",
            "/cms/api/cdn/v1/popups",
            "/cms/api/cdn/v1/products",
            "/cms/api/cdn/v1/taxonomies/skin-concern",
            "/cms/api/cdn/v1/sitemap",
            "/cms/api/cdn/v1/sitemap",
            "/cms/api/cdn/v1/robots",
            "/cms/api/cdn/v1/schema",
            "/cms/api/cdn/v1/global",
        ])
        XCTAssertEqual(requests[0].queryItems, ["path": "/services", "loggedIn": "true", "region": "ireland"])
        XCTAssertEqual(requests[1].queryItems, ["everyPage": "true", "region": "ireland"])
        XCTAssertEqual(requests[2].queryItems, ["path": "/", "region": "ireland"])
        XCTAssertEqual(requests[3].queryItems, ["region": "ireland", "page": "2", "perPage": "12", "filter": "acne"])
        XCTAssertEqual(requests[4].queryItems, ["locale": "ga-IE"])
        XCTAssertEqual(requests[5].queryItems, [:])
        XCTAssertEqual(requests[6].queryItems, ["region": "ireland", "page": "2"])
        XCTAssertEqual(requests[9].queryItems, ["key": "footer", "region": "ireland"])
        XCTAssertEqual(taxonomy.terms.first?.label, "Acne")
        XCTAssertFalse(robots.indexable)
        XCTAssertEqual(schema.components.first?.allowedChildren, "*")
        XCTAssertEqual(footer.fields["copyright"]?.stringValue, "© Acme Clinic")
    }

    func testLocalesFilterByRegion() async throws {
        let regions = #"""
        {"data":[{"key":"ireland","name":"Ireland","locales":[{"code":"en-IE","name":"English (Ireland)","isDefault":true},{"code":"ga-IE","name":"Irish","isDefault":false}]},{"key":"uk","name":"United Kingdom","locales":[{"code":"en-GB","name":"English (UK)","isDefault":true}]}]}
        """#
        let cms = try client(.json(regions), .json(regions), .json(regions))
        let ireland = try await cms.locales()
        XCTAssertEqual(ireland.map(\.code), ["en-IE", "ga-IE"])
        let uk = try await cms.locales(region: "uk")
        XCTAssertEqual(uk.map(\.code), ["en-GB"])
        let all = try await cms.regions()
        XCTAssertEqual(all.count, 2)
    }

    // MARK: - Decoding

    func testDecodesPagesComponentsAndReferences() async throws {
        let cms = try client(.fixture("page"))
        let page = try await cms.page("/services/consultations")

        XCTAssertEqual(page.name, "Consultations")
        XCTAssertEqual(page.version, 7)
        XCTAssertTrue(page.meta.fallbackApplied)
        XCTAssertEqual(page.meta.requestedLocale, "ga-IE")
        XCTAssertEqual(page.meta.references, false)
        XCTAssertEqual(page.fields["title"]?.stringValue, "Book a consultation")
        XCTAssertEqual(page.seo?.openGraph?.siteName, "Acme Clinic")
        XCTAssertEqual(page.seo?.jsonLd.first?["@type"], "WebPage")

        let hero = page.components[0]
        XCTAssertEqual(hero.children["actions"]?.first?.variant, "primary")
        XCTAssertEqual(hero.children["actions"]?.first?.schemaVersion, 2)

        struct Hero: CMSBlockFields {
            static let blockType = "hero"
            let heading: String
            let cta: CMSLink?
        }
        let heroFields = try XCTUnwrap(try hero.decode(Hero.self))
        XCTAssertEqual(heroFields.cta?.href, "/book")
        XCTAssertNil(try page.components[1].decode(Hero.self))

        struct Faq: Decodable, Sendable, Equatable {
            let question: String
        }
        struct FaqList: CMSBlockFields {
            static let blockType = "faqList"
            let heading: String
            let questions: [CMSReference<Faq>]
        }
        let faq = try XCTUnwrap(try page.components[1].decode(FaqList.self))
        XCTAssertEqual(faq.questions.count, 2)
        XCTAssertEqual(faq.questions[0].entry?.fields.question, "Can I cancel at any time?")
        XCTAssertEqual(faq.questions[1], .id("66f1c0ffee0000000000b008"))

        struct PageFields: Decodable {
            let title: String
            let heroImage: CMSImage?
        }
        let fields = try page.fields(as: PageFields.self)
        XCTAssertEqual(fields.heroImage?.width, 1600)
        XCTAssertEqual(fields.heroImage?.url(width: 640)?.absoluteString, "https://api.example.com/cms/uploads/hero.jpg?w=640")
    }

    func testDecodesYourOwnPageType() async throws {
        struct MyPage: Decodable {
            struct Fields: Decodable { let title: String }
            let name: String
            let fields: Fields
        }
        let cms = try client(.fixture("page"))
        let page = try await cms.content(MyPage.self, path: "/services/consultations")
        XCTAssertEqual(page.fields.title, "Book a consultation")
    }

    func testDecodesBannersWithUnknownBlocksAndNext() async throws {
        let cms = try client(.fixture("banners"))
        let banners = try await cms.banners(.path("/services/consultations"))
        let banner = try XCTUnwrap(banners.items.first)

        XCTAssertEqual(banners.serverTime, "2026-10-17T10:00:00.000Z")
        XCTAssertEqual(banner.blocks.count, 3)
        guard case .message(_, let text, let segments) = banner.blocks[0] else { return XCTFail("Expected a message") }
        XCTAssertEqual(text, "Free consultations this week")
        XCTAssertEqual(segments.first?.highlight, true)
        guard case .button(_, _, let link, let style) = banner.blocks[1] else { return XCTFail("Expected a button") }
        XCTAssertEqual(link?.target, "_blank")
        XCTAssertEqual(style, "primary")
        guard case .unknown(let id, let type, let value) = banner.blocks[2] else { return XCTFail("Expected an unknown block") }
        XCTAssertEqual(id, "b3")
        XCTAssertEqual(type, "sparkles")
        XCTAssertEqual(value["intensity"]?.intValue, 3)
        XCTAssertEqual(banner.countdown?.display, "countdown")
        XCTAssertEqual(banner.next?.text, "Winter offers")
        XCTAssertEqual(banner.next?.startsAt, "2026-10-20T22:59:00.000Z")
        XCTAssertNil(banner.next?.next)

        let encoded = try JSONEncoder().encode(banner)
        let decoded = try JSONDecoder().decode(CMSBanner.self, from: encoded)
        XCTAssertEqual(decoded, banner)
    }

    func testJSONValueRoundTrips() throws {
        let value: JSONValue = ["title": "Hi", "count": 3, "ratio": 0.5, "on": true, "none": nil, "list": [1, "two"]]
        let data = try JSONEncoder().encode(value)
        XCTAssertEqual(try JSONDecoder().decode(JSONValue.self, from: data), value)
        XCTAssertEqual(value["count"]?.intValue, 3)
        XCTAssertEqual(value["ratio"]?.doubleValue, 0.5)
        XCTAssertEqual(value["on"]?.boolValue, true)
        XCTAssertEqual(value["none"]?.isNull, true)
        XCTAssertEqual(value["list"]?[1]?.stringValue, "two")
        XCTAssertNil(value["missing"])
    }

    func testDecodingErrorsAreWrapped() async throws {
        let cms = try client(.json(#"{"data":{"key":"main"}}"#))
        do {
            _ = try await cms.navigation("main")
            XCTFail("Expected an error")
        } catch let error as CMSOrbitError {
            guard case .decoding = error else { return XCTFail("\(error)") }
        }
    }

    // MARK: - Errors

    func testMapsErrorAnswers() async throws {
        let cms = try client(
            .json(#"{"error":{"code":"unauthorized","message":"The API key was refused"}}"#, status: 401),
            .json(#"{"error":{"code":"not_found","message":"Content not found"}}"#, status: 404),
            .json(#"{"error":{"code":"rate_limited","message":"Too many requests; try again shortly"}}"#, status: 429, headers: ["Retry-After": "23"]),
            .json(#"{"error":{"code":"bad_request","message":"Unknown sort"}}"#, status: 400),
            .json(#"{"error":{"code":"internal_error","message":"The request failed"}}"#, status: 500),
            .json(#"{"error":"not_found","message":"There is nothing at this address."}"#, status: 404)
        )

        await assertThrows(.unauthorized(message: "The API key was refused")) { _ = try await cms.page("/") }
        await assertThrows(.notFound(message: "Content not found")) { _ = try await cms.page("/") }
        await assertThrows(.rateLimited(retryAfter: 23, message: "Too many requests; try again shortly")) { _ = try await cms.page("/") }
        await assertThrows(.http(status: 400, code: "bad_request", message: "Unknown sort")) { _ = try await cms.list(.init(type: "x")) }
        await assertThrows(.server(status: 500, message: "The request failed")) { _ = try await cms.page("/") }
        await assertThrows(.notFound(message: "There is nothing at this address.")) { _ = try await cms.page("/") }
    }

    func testFindReturnsNilOnlyForNotFound() async throws {
        let cms = try client(
            .json(#"{"error":{"code":"not_found","message":"Content not found"}}"#, status: 404),
            .json(#"{"error":{"code":"not_found","message":"Menu not found"}}"#, status: 404),
            .json(#"{"error":{"code":"not_found","message":"Global not found"}}"#, status: 404),
            .json(#"{"error":{"code":"unauthorized","message":"Nope"}}"#, status: 401)
        )
        let page = try await cms.findPage("/missing")
        XCTAssertNil(page)
        let menu = try await cms.findNavigation("missing")
        XCTAssertNil(menu)
        let global = try await cms.findGlobal("missing")
        XCTAssertNil(global)
        await assertThrows(.unauthorized(message: "Nope")) { _ = try await cms.findPage("/") }
    }

    func testRetriesServerErrorsAndConnectionFailures() async throws {
        let cms = try client(
            retries: 2,
            .json(#"{"error":{"code":"internal_error","message":"The request failed"}}"#, status: 503),
            .failing(.networkConnectionLost),
            .json(#"{"data":{"key":"main","name":"Main menu","items":[]}}"#)
        )
        let menu = try await cms.navigation("main")
        XCTAssertEqual(menu.name, "Main menu")
        XCTAssertEqual(StubProtocol.requests.count, 3)
    }

    func testDoesNotRetryClientErrors() async throws {
        let cms = try client(retries: 2, .json(#"{"error":{"code":"unauthorized","message":"No"}}"#, status: 401))
        await assertThrows(.unauthorized(message: "No")) { _ = try await cms.page("/") }
        XCTAssertEqual(StubProtocol.requests.count, 1)
    }

    func testConnectionFailuresBecomeUnavailable() async throws {
        let cms = try client(.failing(.timedOut), .failing(.notConnectedToInternet))
        await assertThrows(.unavailable(message: "The CMS did not answer within 5s")) { _ = try await cms.page("/") }
        await assertThrows(.unavailable(message: "The CMS could not be reached")) { _ = try await cms.page("/") }
    }

    // MARK: - Preview

    func testPreviewNeedsAPreviewKey() async throws {
        let cms = try client()
        await assertThrows(.previewKeyRequired) { _ = try await cms.page("/", options: .init(preview: true)) }
        XCTAssertTrue(StubProtocol.requests.isEmpty)
    }

    func testPreviewSendsDraftWithThePreviewKey() async throws {
        let cms = try client(previewKey: "cms_sk_preview", .fixture("page"))
        _ = try await cms.page("/services/consultations", options: .init(preview: true))
        let request = try XCTUnwrap(StubProtocol.requests.first)
        XCTAssertEqual(request.queryItems["draft"], "true")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer cms_sk_preview")
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
    }

    func testVerifiesPreviewTokens() async throws {
        let cms = try client(
            .json(#"{"data":{"id":"66f1","name":"Consultations","url":"/services/consultations","contentTypeKey":"page","status":"draft","draft":{"fields":{"title":"New title"},"components":[]}}}"#),
            .json(#"{"error":{"code":"unauthorized","message":"That preview link is invalid or has expired"}}"#, status: 401)
        )
        let link = URL(string: "https://www.example.com/services/consultations?preview=eyJ.abc.def")!
        let token = try XCTUnwrap(CMSOrbitClient.previewToken(from: link))
        XCTAssertEqual(token, "eyJ.abc.def")

        let session = try await cms.verifyPreview(token: token)
        XCTAssertEqual(session.url, "/services/consultations")
        XCTAssertEqual(session.draft["fields"]?["title"], "New title")

        let request = try XCTUnwrap(StubProtocol.requests.first)
        XCTAssertEqual(request.path, "/cms/preview")
        XCTAssertEqual(request.queryItems, ["token": "eyJ.abc.def"])
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))

        await assertThrows(.unauthorized(message: "That preview link is invalid or has expired")) {
            _ = try await cms.verifyPreview(token: "expired")
        }
        XCTAssertNil(CMSOrbitClient.previewToken(from: URL(string: "https://www.example.com/")!))
    }

    // MARK: - GraphQL and raw requests

    func testGraphQL() async throws {
        struct Answer: Decodable { let page: [String: String] }
        let cms = try client(
            .json(#"{"data":{"page":{"name":"Home"}}}"#),
            .json(#"{"data":null,"errors":[{"message":"Unknown field","extensions":{"code":"GRAPHQL_VALIDATION_FAILED"}}]}"#, status: 400)
        )
        let answer = try await cms.graphql("query { page(url: \"/\") { name } }", variables: ["region": "ie"], as: Answer.self)
        XCTAssertEqual(answer.page["name"], "Home")

        let request = try XCTUnwrap(StubProtocol.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.path, "/cms/api/cdn/graphql")
        let body = try JSONDecoder().decode(JSONValue.self, from: try XCTUnwrap(request.httpBody))
        XCTAssertEqual(body["variables"]?["region"], "ie")

        await assertThrows(.graphQL(code: "GRAPHQL_VALIDATION_FAILED", message: "Unknown field")) {
            _ = try await cms.graphql("query { nope }", as: Answer.self)
        }
    }

    func testRawGet() async throws {
        let cms = try client(.json(#"{"data":{"ok":true}}"#))
        let value = try await cms.get(JSONValue.self, path: "/content", query: ["url": "/", "region": "uk"])
        XCTAssertEqual(value["ok"], true)
        XCTAssertEqual(StubProtocol.requests.first?.queryItems, ["url": "/", "region": "uk"])
    }

    func testImageAddresses() {
        XCTAssertEqual(CMSImages.url("https://cdn.example.com/a.jpg", width: 640), "https://cdn.example.com/a.jpg")
        XCTAssertEqual(CMSImages.url("https://api.example.com/cms/uploads/a.jpg?v=2", width: 640, format: .webp), "https://api.example.com/cms/uploads/a.jpg?v=2&w=640&format=webp")
        XCTAssertEqual(CMSImages.variants("https://api.example.com/cms/uploads/a.jpg", width: 1000).map(\.width), [640, 960, 1000])
    }

    // MARK: - Helpers

    private func assertThrows(
        _ expected: CMSOrbitError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () async throws -> Void
    ) async {
        do {
            try await body()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? CMSOrbitError, expected, file: file, line: line)
        }
    }
}
