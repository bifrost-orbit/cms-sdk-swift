import Foundation

public enum CMSImageFormat: String, Sendable, Hashable {
    case webp
    case avif
}

public enum CMSImages {
    static let srcsetWidths = [320, 480, 640, 768, 960, 1280, 1600, 1920]

    /// The address of an uploaded image resized to `width` and converted to `format`. Other addresses are returned unchanged.
    public static func url(_ url: String, width: Int? = nil, format: CMSImageFormat? = nil) -> String {
        guard url.contains("/uploads/") else { return url }
        let parts = url.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let path = String(parts[0])
        var items = parts.count > 1 ? (URLComponents(string: "?\(parts[1])")?.queryItems ?? []) : []
        func set(_ name: String, _ value: String) {
            items.removeAll { $0.name == name }
            items.append(URLQueryItem(name: name, value: value))
        }
        if let width { set("w", String(width)) }
        if let format { set("format", format.rawValue) }
        guard !items.isEmpty else { return path }
        var components = URLComponents()
        components.queryItems = items
        return "\(path)?\(components.percentEncodedQuery ?? "")"
    }

    /// The widths worth asking for, smaller than the original, as `(width, address)` pairs.
    public static func variants(_ url: String, width: Int?) -> [(width: Int, url: String)] {
        guard url.contains("/uploads/") else { return [] }
        let widths = srcsetWidths.filter { width == nil || $0 < width! }
        var variants = widths.map { ($0, Self.url(url, width: $0)) }
        if let width, !widths.isEmpty { variants.append((width, url)) }
        return variants
    }
}

extension CMSImage {
    /// This image resized to `width`, for a sharp picture without downloading the original.
    public func url(width: Int? = nil, format: CMSImageFormat? = nil) -> URL? {
        URL(string: CMSImages.url(url, width: width, format: format))
    }
}

extension CMSImageSummary {
    public func url(width: Int? = nil, format: CMSImageFormat? = nil) -> URL? {
        URL(string: CMSImages.url(url, width: width, format: format))
    }
}
