# Changelog

## 0.2.0 (8 November 2026)

- `CMSWebhook.verify(secret:timestamp:signature:body:)` checks a webhook message on a Swift server: the HMAC-SHA256 signature in `x-orbit-signature`, compared in constant time, and the `x-orbit-timestamp` within five minutes, the same rules as the JavaScript and PHP SDKs. `CMSWebhook.parse(…)` also answers the message's `event` and `data`, or `nil` when it is not genuine. It uses CryptoKit, so it is there on Apple platforms (macOS, iOS, tvOS and watchOS) and not on Linux.
- The package no longer includes the SDK's tests, so Xcode and Swift Package Manager fetch only the library. The README's examples use Northwilds, our demo brand.
- When the organisation's CMS Orbit trial or plan has ended, the delivery API and GraphQL answer 402. Every call then throws the new `CMSOrbitError.subscriptionInactive` (status `402`, code `subscription_inactive`) straight away, without retrying, whatever code the API sends, and `error.isSubscriptionInactive` tells you. A `switch` over every case of `CMSOrbitError` needs the new case. `CMSOrbitClient.version` and the User-Agent are now `0.2.0`.
- `CMSImages.variants` offers 320, 480, 640, 768, 960, 1280, 1600 and 1920 pixels wide instead of 640, 960, 1280 and 1920, the widths CMS Orbit makes, so phones and small cards load a photo close to the size they show it at.
- Pages carry `id`, the entry's id, and `insights`, a `CMSInsightsSite` when the space is connected to Insights Orbit. Both are optional, so answers from an older CMS Orbit still decode.
- `CMSInsights.tags(page:)` writes the Insights Orbit script with the site key and `<meta name="insights-content">` with the entry's id, for server-rendered pages. With `waitForConsent`, the script waits for `insights.consent()` before counting. Without a site key it writes nothing.
