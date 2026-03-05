import Foundation

struct MediaMetadata: Codable, Equatable {
    struct FormatInfo: Codable, Equatable {
        let filename: String?
        let formatName: String?
        let formatLongName: String?
        let duration: String?
        let size: String?
        let bitRate: String?
        let tags: [String: String]?
    }

    struct StreamInfo: Codable, Equatable, Identifiable {
        let index: Int
        let codecName: String?
        let codecLongName: String?
        let codecType: String?
        let width: Int?
        let height: Int?
        let pixFmt: String?
        let avgFrameRate: String?
        let rFrameRate: String?
        let bitRate: String?
        let colorTransfer: String?
        let colorSpace: String?
        let colorPrimaries: String?
        let channelLayout: String?
        let sampleRate: String?
        let tags: [String: String]?

        var id: Int { index }
        var isVideo: Bool { codecType == "video" }
        var isAudio: Bool { codecType == "audio" }
        var isSubtitle: Bool { codecType == "subtitle" }
        var frameRateValue: Double? {
            Self.parseFraction(avgFrameRate ?? rFrameRate)
        }

        private static func parseFraction(_ text: String?) -> Double? {
            guard let text, !text.isEmpty else { return nil }
            let parts = text.split(separator: "/")
            guard parts.count == 2,
                  let numerator = Double(parts[0]),
                  let denominator = Double(parts[1]),
                  denominator != 0 else {
                return Double(text)
            }
            return numerator / denominator
        }
    }

    struct ChapterInfo: Codable, Equatable {
        let chapterID: Int?
        let startTime: String?
        let endTime: String?
        let tags: [String: String]?

        enum CodingKeys: String, CodingKey {
            case chapterID = "id"
            case startTime
            case endTime
            case tags
        }

        var stableID: String {
            "\(chapterID ?? -1)-\(startTime ?? "0")"
        }

        var chapterTitle: String {
            tags?["title"] ?? "Chapter \(chapterID ?? 0)"
        }
    }

    let format: FormatInfo
    let streams: [StreamInfo]
    let chapters: [ChapterInfo]

    var durationSeconds: Double? {
        guard let duration = format.duration else { return nil }
        return Double(duration)
    }

    var fileSizeBytes: Int64? {
        guard let size = format.size else { return nil }
        return Int64(size)
    }

    var videoStream: StreamInfo? {
        streams.first(where: \.isVideo)
    }

    var audioStreams: [StreamInfo] {
        streams.filter(\.isAudio)
    }

    var subtitleStreams: [StreamInfo] {
        streams.filter(\.isSubtitle)
    }

    var isHDR: Bool {
        guard let videoStream else { return false }
        let transfer = videoStream.colorTransfer?.lowercased() ?? ""
        return transfer.contains("smpte2084") || transfer.contains("arib-std-b67")
    }
}

extension MediaMetadata.ChapterInfo: Identifiable {
    var id: String { stableID }
}

struct FFprobePayload: Codable, Equatable {
    let format: MediaMetadata.FormatInfo
    let streams: [MediaMetadata.StreamInfo]
    let chapters: [MediaMetadata.ChapterInfo]?
}
