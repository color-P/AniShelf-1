import Foundation

enum VideoExtractorError: LocalizedError {
    case invalidURL
    case badResponse
    case noMediaFound

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "请输入有效的网址或媒体链接。"
        case .badResponse: return "页面请求失败，请检查链接或稍后重试。"
        case .noMediaFound: return "没有从当前页面提取到媒体地址。可尝试使用“浏览器”标签页打开并播放视频后再提取。"
        }
    }
}

struct XTwitterTweet {
    let screenName: String?
    let statusID: String
    let pageURL: URL

    init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let parts = components.path.split(separator: "/").map(String.init)
        guard let statusIndex = parts.firstIndex(of: "status") else {
            return nil
        }

        let idIndex = parts.index(after: statusIndex)
        guard idIndex < parts.endIndex else {
            return nil
        }

        let rawID = parts[idIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawID.isEmpty,
              rawID.rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) == nil else {
            return nil
        }

        let possibleScreenName = statusIndex > 0 ? parts[statusIndex - 1] : nil
        if possibleScreenName == "i" || possibleScreenName == "web" {
            screenName = nil
        } else {
            screenName = possibleScreenName
        }
        statusID = rawID
        pageURL = url
    }
}

struct XTwitterResponse: Decodable {
    let code: Int?
    let error_code: String?
    let message: String?
    let text: String?
    let user_screen_name: String?
    let mediaURLs: [String]?
    let media_extended: [XTwitterMedia]?
    let tweet: XTwitterAPITweet?
}

struct XTwitterAPITweet: Decodable {
    let text: String?
    let author: XTwitterAuthor?
    let media: XTwitterMediaContainer?
}

struct XTwitterAuthor: Decodable {
    let screen_name: String?
}

struct XTwitterMediaContainer: Decodable {
    let all: [XTwitterMedia]?
    let videos: [XTwitterMedia]?
}

struct XTwitterMedia: Decodable {
    let url: String?
    let type: String?
    let container: String?
    let bitrate: Int?
    let width: Int?
    let height: Int?
    let formats: [XTwitterMedia]?
    let variants: [XTwitterMedia]?
}

final class VideoExtractorEngine {
    static let userAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func extract(from url: URL) async throws -> [MediaCandidate] {
        if Self.isXTwitterURL(url) {
            return try await extractXTwitter(from: url)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(
            "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            forHTTPHeaderField: "Accept"
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else {
            throw VideoExtractorError.badResponse
        }

        let text = String(data: data, encoding: .utf8)
            ?? String(decoding: data, as: UTF8.self)

        let candidates = Self.extract(
            fromText: text,
            baseURL: response.url ?? url,
            pageURL: url
        )

        guard !candidates.isEmpty else {
            throw VideoExtractorError.noMediaFound
        }

        return candidates
    }

    static func isXTwitterURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "x.com"
            || host.hasSuffix(".x.com")
            || host == "twitter.com"
            || host.hasSuffix(".twitter.com")
    }

    private func extractXTwitter(from url: URL) async throws -> [MediaCandidate] {
        guard let tweet = XTwitterTweet(url: url) else {
            throw VideoExtractorError.noMediaFound
        }

        var endpoints: [URL] = []
        if let screenName = tweet.screenName {
            endpoints.append(
                URL(string: "https://api.fxtwitter.com/\(screenName)/status/\(tweet.statusID)")!
            )
            endpoints.append(
                URL(string: "https://api.vxtwitter.com/\(screenName)/status/\(tweet.statusID)")!
            )
        } else {
            endpoints.append(
                URL(string: "https://api.fxtwitter.com/i/status/\(tweet.statusID)")!
            )
        }

        var lastError: Error = VideoExtractorError.noMediaFound

        for endpoint in endpoints {
            do {
                var request = URLRequest(url: endpoint)
                request.timeoutInterval = 25
                request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
                request.setValue("application/json", forHTTPHeaderField: "Accept")

                let (data, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    lastError = VideoExtractorError.badResponse
                    continue
                }

                let decoded = try JSONDecoder().decode(XTwitterResponse.self, from: data)
                if decoded.error_code != nil {
                    lastError = VideoExtractorError.noMediaFound
                    continue
                }
                if let code = decoded.code, !(200..<300).contains(code) {
                    lastError = VideoExtractorError.noMediaFound
                    continue
                }

                var candidates = Self.candidatesFromXTwitterResponse(
                    decoded,
                    tweet: tweet
                )

                if candidates.isEmpty,
                   let mediaURLs = decoded.mediaURLs {
                    candidates = Self.candidates(
                        from: mediaURLs,
                        baseURL: endpoint,
                        pageURL: url
                    )
                }

                guard !candidates.isEmpty else {
                    lastError = VideoExtractorError.noMediaFound
                    continue
                }

                return candidates
            } catch {
                lastError = error
            }
        }

        throw lastError
    }

    private static func candidatesFromXTwitterResponse(
        _ response: XTwitterResponse,
        tweet: XTwitterTweet
    ) -> [MediaCandidate] {
        let flatTitle = response.text?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let nestedTitle = response.tweet?.text?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let title = flatTitle ?? nestedTitle

        let screenName = response.user_screen_name
            ?? response.tweet?.author?.screen_name

        var mediaItems: [XTwitterMedia] = []
        if let media_extended = response.media_extended {
            mediaItems.append(contentsOf: media_extended)
        }
        if let videos = response.tweet?.media?.videos {
            mediaItems.append(contentsOf: videos)
        }
        if let all = response.tweet?.media?.all {
            mediaItems.append(contentsOf: all)
        }

        var expandedItems: [XTwitterMedia] = []
        for item in mediaItems {
            expandedItems.append(item)
            if let formats = item.formats {
                expandedItems.append(contentsOf: formats)
            }
            if let variants = item.variants {
                expandedItems.append(contentsOf: variants)
            }
        }

        var seen = Set<String>()
        var media: [MediaCandidate] = []
        for item in expandedItems {
            guard let rawURL = item.url,
                  let url = resolvedURL(from: rawURL, baseURL: nil) else {
                continue
            }

            let key = url.absoluteString
            guard !seen.contains(key) else { continue }
            seen.insert(key)

            let kind = kind(for: url)
            let isVideoLike = item.type?.lowercased() == "video"
                || item.type?.lowercased() == "gif"
                || item.container?.lowercased() == "mp4"
                || kind.isVideo
            guard isVideoLike else { continue }

            if kind == .m3u8 {
                continue
            }

            let finalKind = kind == .other ? .mp4 : kind
            media.append(
                MediaCandidate(
                url: url,
                kind: finalKind,
                source: "X/Twitter 解析",
                pageURL: tweet.pageURL,
                title: title ?? screenName,
                quality: Self.qualityLabel(for: item, url: url)
                )
            )
        }

        return media.sorted { lhs, rhs in
            qualityScore(for: lhs.url, quality: lhs.quality, bitrate: nil)
                > qualityScore(for: rhs.url, quality: rhs.quality, bitrate: nil)
        }
    }

    private static func qualityLabel(
        for item: XTwitterMedia,
        url: URL
    ) -> String? {
        let text = url.absoluteString
        if let match = firstMatch(
            for: #"\d{2,4}x\d{2,4}"#,
            in: text
        ) {
            return match
        }

        if let width = item.width, let height = item.height {
            return "\(width)×\(height)"
        }

        if let bitrate = item.bitrate, bitrate > 0 {
            if bitrate >= 1_000_000 {
                return String(format: "%.1f Mbps", Double(bitrate) / 1_000_000)
            }
            return "\(bitrate / 1_000) Kbps"
        }

        return nil
    }

    private static func qualityScore(
        for url: URL,
        quality: String?,
        bitrate: Int?
    ) -> Int {
        if let quality,
           let match = firstMatch(for: #"\d{2,4}x\d{2,4}"#, in: quality),
           let separator = match.firstIndex(of: "x") {
            let widthText = String(match[..<separator])
            let heightText = String(match[match.index(after: separator)...])
            if let width = Int(widthText), let height = Int(heightText) {
                return width * height
            }
        }

        if let bitrate {
            return bitrate
        }

        let text = url.absoluteString
        if let match = firstMatch(for: #"\d{2,4}x\d{2,4}"#, in: text),
           let separator = match.firstIndex(of: "x") {
            let widthText = String(match[..<separator])
            let heightText = String(match[match.index(after: separator)...])
            if let width = Int(widthText), let height = Int(heightText) {
                return width * height
            }
        }

        return 0
    }

    private static func firstMatch(
        for pattern: String,
        in text: String
    ) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else {
            return nil
        }
        return (text as NSString).substring(with: match.range)
    }

    static func normalizedURL(from text: String) -> URL? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if !value.contains("://") {
            value = "https://" + value
        }
        guard let url = URL(string: value), url.host != nil else {
            return nil
        }
        return url
    }

    static func extract(
        fromText text: String,
        baseURL: URL?,
        pageURL: URL?
    ) -> [MediaCandidate] {
        var prepared = text
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "&amp;", with: "&")

        // 让常见的 HTML 实体还原，避免 URL 中的 & 被截断。
        prepared = prepared
            .replacingOccurrences(of: "&#x2F;", with: "/")
            .replacingOccurrences(of: "&#47;", with: "/")

        var rawValues = Set<String>()

        let directPattern =
            #"https?://[^"'<>\s()\[\]{}]+?\.(?:mp4|m3u8|mov|m4v|webm|mkv|mp3|m4a)(?:\?[^"'<>\s()\[\]{}]*)?(?:#[^"'\s]*)?\b"#
        for match in matches(for: directPattern, in: prepared) {
            rawValues.insert(match)
        }

        let attributePattern =
            #"(?:src|href|content|contentUrl|url)\s*=\s*["']([^"']+?)["']"#
        for capture in captureGroups(for: attributePattern, in: prepared) {
            if looksLikeMediaURL(capture) {
                rawValues.insert(capture)
            }
        }

        let metaPatterns = [
            #"property\s*=\s*["']og:video(?::url|:secure_url)?["'][^>]*content\s*=\s*["']([^"']+)["']"#,
            #"content\s*=\s*["']([^"']+)["'][^>]*property\s*=\s*["']og:video(?::url|:secure_url)?["']"#,
            #"name\s*=\s*["']twitter:player(?::stream)?["'][^>]*content\s*=\s*["']([^"']+)["']"#
        ]
        for pattern in metaPatterns {
            for capture in captureGroups(for: pattern, in: prepared) {
                rawValues.insert(capture)
            }
        }

        return candidates(from: Array(rawValues), baseURL: baseURL, pageURL: pageURL)
    }

    static func candidates(
        from values: [String],
        baseURL: URL?,
        pageURL: URL?
    ) -> [MediaCandidate] {
        var seen = Set<String>()
        var result: [MediaCandidate] = []

        for raw in values {
            guard let url = resolvedURL(from: raw, baseURL: baseURL) else { continue }
            let kind = kind(for: url)
            guard kind != .other else { continue }

            let key = url.absoluteString
            guard !seen.contains(key) else { continue }
            seen.insert(key)

            result.append(
                MediaCandidate(
                    url: url,
                    kind: kind,
                    source: "网页媒体",
                    pageURL: pageURL
                )
            )
        }

        return result
    }

    static func resolvedURL(from raw: String, baseURL: URL?) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("//"), let scheme = baseURL?.scheme {
            return URL(string: "\(scheme):\(trimmed)")
        }

        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }

        if let baseURL {
            return URL(string: trimmed, relativeTo: baseURL)?.absoluteURL
        }

        return nil
    }

    static func kind(for url: URL) -> MediaKind {
        let ext = url.pathExtension.lowercased()
        return MediaKind(rawValue: ext) ?? .other
    }

    private static func looksLikeMediaURL(_ value: String) -> Bool {
        let lower = value.lowercased()
        return lower.contains(".m3u8")
            || lower.contains(".mp4")
            || lower.contains(".mov")
            || lower.contains(".m4v")
            || lower.contains(".webm")
            || lower.contains(".mkv")
            || lower.contains(".mp3")
            || lower.contains(".m4a")
            || lower.contains(".jpg")
            || lower.contains(".jpeg")
            || lower.contains(".png")
            || lower.contains(".gif")
            || lower.contains(".webp")
            || lower.contains(".bmp")
            || lower.contains(".heic")
    }

    private static func matches(for pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).map {
            (text as NSString).substring(with: $0.range)
        }
    }

    private static func captureGroups(for pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            let range = match.range(at: 1)
            guard range.location != NSNotFound else { return nil }
            return (text as NSString).substring(with: range)
        }
    }
}
