import Foundation

enum MediaKind: String, Codable, CaseIterable {
    case mp4
    case m3u8
    case mov
    case m4v
    case webm
    case mkv
    case mp3
    case m4a
    case jpg
    case jpeg
    case png
    case gif
    case webp
    case bmp
    case heic
    case other

    var displayName: String {
        switch self {
        case .mp4: return "MP4 视频"
        case .m3u8: return "HLS 流媒体"
        case .mov: return "MOV 视频"
        case .m4v: return "M4V 视频"
        case .webm: return "WebM 视频"
        case .mkv: return "MKV 视频"
        case .mp3: return "MP3 音频"
        case .m4a: return "M4A 音频"
        case .jpg, .jpeg: return "JPEG 图片"
        case .png: return "PNG 图片"
        case .gif: return "GIF 图片"
        case .webp: return "WebP 图片"
        case .bmp: return "BMP 图片"
        case .heic: return "HEIC 图片"
        case .other: return "媒体文件"
        }
    }

    var isVideo: Bool {
        switch self {
        case .mp3, .m4a, .other, .jpg, .jpeg, .png, .gif, .webp, .bmp, .heic:
            return false
        default: return true
        }
    }

    var isImage: Bool {
        switch self {
        case .jpg, .jpeg, .png, .gif, .webp, .bmp, .heic:
            return true
        default:
            return false
        }
    }
}

struct MediaCandidate: Identifiable, Hashable, Codable {
    let id: UUID
    let url: URL
    let kind: MediaKind
    let source: String
    let pageURL: URL?
    let title: String?
    let quality: String?

    init(
        id: UUID = UUID(),
        url: URL,
        kind: MediaKind,
        source: String = "HTML 解析",
        pageURL: URL? = nil,
        title: String? = nil,
        quality: String? = nil
    ) {
        self.id = id
        self.url = url
        self.kind = kind
        self.source = source
        self.pageURL = pageURL
        self.title = title
        self.quality = quality
    }

    var displayTitle: String {
        if let title, !title.isEmpty {
            return title
        }
        let name = url.lastPathComponent
        return name.isEmpty ? url.host ?? "媒体文件" : name
    }

    var fileExtension: String {
        switch kind {
        case .m3u8: return "m3u8"
        case .other: return "bin"
        default: return kind.rawValue
        }
    }
}
