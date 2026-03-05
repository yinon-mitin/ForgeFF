import Combine
import Foundation

@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var records: [JobHistoryRecord] = []

    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = appSupport.appendingPathComponent("ForgeFF", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: nil)
        fileURL = folder.appendingPathComponent("history.json")
        load()
    }

    func append(job: VideoJob) {
        records.insert(.from(job: job), at: 0)
        persist()
    }

    func clear() {
        records.removeAll()
        persist()
    }

    func exportJSON(to url: URL) throws {
        let data = try JSONEncoder.pretty.encode(records)
        try data.write(to: url, options: .atomic)
    }

    func exportCSV(to url: URL) throws {
        let header = "id,sourcePath,outputPath,preset,status,createdAt,completedAt,sourceSize,outputSize,durationSeconds,averageSpeed,resolution,videoCodec,audioCodec,dynamicRange"
        let rows = records.map { record in
            let fields: [String] = [
                record.id.uuidString,
                record.sourcePath,
                record.outputPath ?? "",
                record.presetName,
                record.status.rawValue,
                ISO8601DateFormatter().string(from: record.createdAt),
                record.completedAt.map { ISO8601DateFormatter().string(from: $0) } ?? "",
                record.sourceSize.map(String.init) ?? "",
                record.outputSize.map(String.init) ?? "",
                record.durationSeconds.map { String(format: "%.2f", $0) } ?? "",
                record.averageSpeed.map { String(format: "%.2f", $0) } ?? "",
                record.resolutionDescription,
                record.videoCodec,
                record.audioCodec,
                record.dynamicRange
            ]
            let escapedFields = fields.map(csvEscape)
            return escapedFields.joined(separator: ",")
        }
        let csv = ([header] + rows).joined(separator: "\n")
        guard let data = csv.data(using: String.Encoding.utf8) else { return }
        try data.write(to: url, options: Data.WritingOptions.atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder.iso8601.decode([JobHistoryRecord].self, from: data) else {
            records = []
            return
        }
        records = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder.pretty.encode(records) else { return }
        try? data.write(to: fileURL, options: Data.WritingOptions.atomic)
    }

    private func csvEscape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
