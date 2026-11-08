import Foundation

/// The Insights Orbit script for server-rendered HTML, with the same output as the JavaScript SDK's `CmsInsights`.
public enum CMSInsights {
    public static let script = "https://api.bifrostorbit.com/insights/v1/script.js"

    // [EXPLAIN-D271]
    /// The tags for `<head>`: `<meta name="insights-content">` with the page's entry id and the script with the site key.
    /// An empty string without a site key, from `site` or the page's ``CMSPage/insights``.
    public static func tags(
        page: CMSPage? = nil,
        site: String? = nil,
        contentId: String? = nil,
        src: String = script,
        api: String? = nil,
        disable: [String] = [],
        campaigns: Bool = true,
        waitForConsent: Bool = false
    ) -> String {
        guard let key = [site, page?.insights?.site].compactMap({ $0 }).first(where: { !$0.isEmpty }) else { return "" }
        var tag = "<script defer data-site=\"\(escape(key))\""
        if let api, !api.isEmpty { tag += " data-api=\"\(escape(api))\"" }
        if !disable.isEmpty { tag += " data-disable=\"\(escape(disable.joined(separator: " ")))\"" }
        if campaigns { tag += " data-campaigns" }
        if waitForConsent { tag += " data-consent=\"wait\"" }
        tag += " src=\"\(escape(src))\"></script>"
        guard let entry = contentId ?? page?.id, !entry.isEmpty else { return tag }
        return "<meta name=\"insights-content\" content=\"\(escape(entry))\">\n" + tag
    }

    static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#039;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
