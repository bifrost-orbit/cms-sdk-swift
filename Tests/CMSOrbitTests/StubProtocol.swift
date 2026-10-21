import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import CMSOrbit

struct StubResponse: Sendable {
    var status: Int = 200
    var body: Data = Data()
    var headers: [String: String] = ["Content-Type": "application/json"]
    var failure: URLError.Code?

    static func json(_ string: String, status: Int = 200, headers: [String: String] = [:]) -> StubResponse {
        StubResponse(status: status, body: Data(string.utf8), headers: ["Content-Type": "application/json"].merging(headers) { $1 })
    }

    static func fixture(_ name: String, status: Int = 200) -> StubResponse {
        let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!
        return StubResponse(status: status, body: try! Data(contentsOf: url))
    }

    static func failing(_ code: URLError.Code) -> StubResponse {
        StubResponse(failure: code)
    }
}

private final class StubStore: @unchecked Sendable {
    let lock = NSLock()
    var queue: [StubResponse] = []
    var captured: [URLRequest] = []
}

final class StubProtocol: URLProtocol, @unchecked Sendable {
    private static let store = StubStore()

    static func reset(_ responses: [StubResponse]) {
        store.lock.lock()
        defer { store.lock.unlock() }
        store.queue = responses
        store.captured = []
    }

    static var requests: [URLRequest] {
        store.lock.lock()
        defer { store.lock.unlock() }
        return store.captured
    }

    private static func next(_ request: URLRequest) -> StubResponse {
        store.lock.lock()
        defer { store.lock.unlock() }
        store.captured.append(request)
        if store.queue.isEmpty {
            return .json(#"{"error":{"code":"no_stub","message":"No stubbed response"}}"#, status: 599)
        }
        return store.queue.removeFirst()
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var request = self.request
        if request.httpBody == nil, let stream = request.httpBodyStream {
            request.httpBody = Self.read(stream)
        }
        let stub = Self.next(request)
        if let failure = stub.failure {
            client?.urlProtocol(self, didFailWithError: URLError(failure))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: stub.status, httpVersion: "HTTP/1.1", headerFields: stub.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

extension URLRequest {
    var queryItems: [String: String] {
        let items = URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { _, last in last })
    }

    var path: String { url!.path }
}
