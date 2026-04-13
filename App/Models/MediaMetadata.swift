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

    struct SideDataInfo: Codable, Equatable {
        let sideDataType: String?
        let dvProfile: Int?
        let dvLevel: Int?
        let rpuPresentFlag: Int?
        let elPresentFlag: Int?
        let blPresentFlag: Int?
        let maxContent: Int?
        let maxAverage: Int?

        enum CodingKeys: String, CodingKey {
            case sideDataType
            case dvProfile
            case dvLevel
            case rpuPresentFlag
            case elPresentFlag
            case blPresentFlag
            case maxContent
            case maxAverage
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            sideDataType = try container.decodeIfPresent(String.self, forKey: .sideDataType)
            dvProfile = container.decodeFlexibleInt(forKey: .dvProfile)
            dvLevel = container.decodeFlexibleInt(forKey: .dvLevel)
            rpuPresentFlag = container.decodeFlexibleInt(forKey: .rpuPresentFlag)
            elPresentFlag = container.decodeFlexibleInt(forKey: .elPresentFlag)
            blPresentFlag = container.decodeFlexibleInt(forKey: .blPresentFlag)
            maxContent = container.decodeFlexibleInt(forKey: .maxContent)
            maxAverage = container.decodeFlexibleInt(forKey: .maxAverage)
        }
    }

    struct StreamInfo: Codable, Equatable, Identifiable {
        let index: Int
        let codecName: String?
        let codecLongName: String?
        let profile: String?
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
        let sideDataList: [SideDataInfo]?

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

        private var normalizedTags: [String: String] {
            Dictionary(uniqueKeysWithValues: (tags ?? [:]).map { key, value in
                (key.lowercased(), value.lowercased())
            })
        }

        private var normalizedProfile: String {
            profile?.lowercased() ?? ""
        }

        private var normalizedTransfer: String {
            colorTransfer?.lowercased() ?? ""
        }

        private var normalizedPrimaries: String {
            colorPrimaries?.lowercased() ?? ""
        }

        private var normalizedColorSpace: String {
            colorSpace?.lowercased() ?? ""
        }

        private var normalizedPixelFormat: String {
            pixFmt?.lowercased() ?? ""
        }

        private var normalizedSideDataTypes: [String] {
            (sideDataList ?? []).compactMap { $0.sideDataType?.lowercased() }
        }

        private var hasMasteringDisplayMetadata: Bool {
            normalizedSideDataTypes.contains { $0.contains("mastering display") }
        }

        private var hasContentLightLevelMetadata: Bool {
            normalizedSideDataTypes.contains { $0.contains("content light") }
        }

        private var hasHDRSideData: Bool {
            hasMasteringDisplayMetadata || hasContentLightLevelMetadata
        }

        private var hasBT2020Colorimetry: Bool {
            normalizedPrimaries.contains("bt2020") || normalizedColorSpace.contains("bt2020")
        }

        private var looksLikePQ: Bool {
            normalizedTransfer.contains("smpte2084") ||
            normalizedTransfer.contains("st2084") ||
            normalizedTransfer == "pq"
        }

        private var looksLikeHLG: Bool {
            normalizedTransfer.contains("arib-std-b67") ||
            normalizedTransfer.contains("hlg")
        }

        private var looksLikeTenBitHDR: Bool {
            normalizedPixelFormat.contains("10") || normalizedProfile.contains("main 10")
        }

        private var dolbyVisionProfile: Int? {
            if let profile = sideDataList?.compactMap(\.dvProfile).first {
                return profile
            }

            for key in ["dv_profile", "dovi_profile", "dolby_vision_profile"] {
                if let value = normalizedTags[key], let profile = Int(value) {
                    return profile
                }
            }

            return nil
        }

        private var isDolbyVision: Bool {
            if dolbyVisionProfile != nil {
                return true
            }

            if normalizedProfile.contains("dolby vision") {
                return true
            }

            if normalizedSideDataTypes.contains(where: { $0.contains("dovi") || $0.contains("dolby vision") }) {
                return true
            }

            return normalizedTags.contains { key, value in
                key.contains("dovi") ||
                key.contains("dolby") ||
                value.contains("dolby vision") ||
                value.contains("dovi")
            }
        }

        var dynamicRangeDescription: String? {
            if let dolbyVisionProfile {
                return "Dolby Vision (Profile \(dolbyVisionProfile))"
            }
            if isDolbyVision {
                return "Dolby Vision"
            }
            if looksLikeHLG {
                return "HLG"
            }
            if looksLikePQ {
                return hasBT2020Colorimetry || hasHDRSideData ? "HDR10 (PQ)" : "HDR (PQ)"
            }
            if hasBT2020Colorimetry && (hasHDRSideData || looksLikeTenBitHDR) {
                return "HDR (BT.2020)"
            }
            if hasHDRSideData {
                return "HDR"
            }
            return nil
        }

        var isHDRVideo: Bool {
            dynamicRangeDescription != nil
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
        videoStream?.isHDRVideo ?? false
    }

    var dynamicRangeDescription: String {
        videoStream?.dynamicRangeDescription ?? "SDR"
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

private extension KeyedDecodingContainer {
    func decodeFlexibleInt(forKey key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Int(value)
        }
        return nil
    }
}
