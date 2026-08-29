import AppKit
import CryptoKit
import Foundation

@MainActor
final class AppUpdateService: ObservableObject {
    struct ReleaseInfo: Equatable, Identifiable {
        let tagName: String
        let version: String
        let releaseURL: URL
        let archiveURL: URL
        let checksumURL: URL

        var id: String { tagName }
    }

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(ReleaseInfo)
        case downloading
        case ready(ReleaseInfo)
        case failed(String)
    }

    private struct GitHubRelease: Decodable {
        let tagName: String
        let htmlURL: URL
        let draft: Bool
        let prerelease: Bool
        let assets: [GitHubAsset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case draft
            case prerelease
            case assets
        }
    }

    private struct GitHubAsset: Decodable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    private static let owner = "yinon-mitin"
    private static let repository = "ForgeFF"
    private static let latestReleaseURL = URL(string: "https://api.github.com/repos/\(owner)/\(repository)/releases/latest")!

    @Published private(set) var state: State = .idle
    @Published private(set) var lastCheckedAt: Date?

    func checkForUpdates() async {
        guard state != .checking else { return }
        state = .checking

        do {
            var request = URLRequest(url: Self.latestReleaseURL)
            request.timeoutInterval = 15
            request.setValue("ForgeFF/\(BuildIdentity.versionString)", forHTTPHeaderField: "User-Agent")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                throw UpdateError.invalidResponse
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            guard !release.draft, !release.prerelease,
                  let releaseInfo = Self.releaseInfo(from: release),
                  Self.isNewerVersion(releaseInfo.version, than: BuildIdentity.versionString) else {
                lastCheckedAt = Date()
                state = .upToDate
                return
            }

            lastCheckedAt = Date()
            state = .available(releaseInfo)
        } catch is CancellationError {
            state = .idle
        } catch {
            state = .failed(Self.userMessage(for: error))
        }
    }

    func downloadAndInstall() async {
        guard case let .available(release) = state else { return }
        state = .downloading

        do {
            let temporaryDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("ForgeFF-update-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)

            let archiveData = try await Self.download(url: release.archiveURL)
            let checksumData = try await Self.download(url: release.checksumURL)
            let checksumText = String(decoding: checksumData, as: UTF8.self)
            guard let expectedChecksum = Self.parseChecksum(checksumText, expectedFilename: Self.expectedAssetNames(for: release.tagName)[0]) else {
                throw UpdateError.invalidChecksum
            }
            guard Self.sha256(of: archiveData) == expectedChecksum else {
                throw UpdateError.checksumMismatch
            }

            let archiveURL = temporaryDirectory.appendingPathComponent(Self.expectedAssetNames(for: release.tagName)[0])
            try archiveData.write(to: archiveURL, options: .atomic)
            let extractionDirectory = temporaryDirectory.appendingPathComponent("extracted", isDirectory: true)
            try FileManager.default.createDirectory(at: extractionDirectory, withIntermediateDirectories: true)
            try Self.runTool("/usr/bin/ditto", arguments: ["-x", "-k", archiveURL.path, extractionDirectory.path])

            let candidateURL = extractionDirectory.appendingPathComponent("ForgeFF.app", isDirectory: true)
            guard let candidateBundle = Bundle(url: candidateURL),
                  candidateBundle.bundleIdentifier == "com.yinonmitin.ForgeFF",
                  let candidateVersion = candidateBundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                  !Self.isNewerVersion(BuildIdentity.versionString, than: candidateVersion) else {
                throw UpdateError.invalidBundle
            }
            try Self.runTool("/usr/bin/codesign", arguments: ["--verify", "--deep", "--strict", candidateURL.path])

            try Self.launchReplacementUpdater(
                newAppURL: candidateURL,
                currentAppURL: Bundle.main.bundleURL,
                stagingDirectoryURL: temporaryDirectory
            )
            state = .ready(release)
            NSApp.terminate(nil)
        } catch is CancellationError {
            state = .available(release)
        } catch {
            state = .failed(Self.userMessage(for: error))
        }
    }

    nonisolated static func expectedAssetNames(for tagName: String) -> [String] {
        let version = normalizedVersion(tagName)
        let archiveName = "ForgeFF-\(version)-macOS.zip"
        return [archiveName, "\(archiveName).sha256"]
    }

    nonisolated static func isNewerVersion(_ candidate: String, than current: String) -> Bool {
        let candidateComponents = versionComponents(candidate)
        let currentComponents = versionComponents(current)
        for index in candidateComponents.indices {
            if candidateComponents[index] != currentComponents[index] {
                return candidateComponents[index] > currentComponents[index]
            }
        }
        return false
    }

    nonisolated static func parseChecksum(_ text: String, expectedFilename: String? = nil) -> String? {
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = line.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count == 2 else { continue }
            let digest = String(parts[0]).lowercased()
            let rawFilename = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            let filename = URL(fileURLWithPath: String(rawFilename.drop(while: { $0 == "*" }))).lastPathComponent
            guard digest.count == 64,
                  digest.allSatisfy({ $0.isHexDigit }),
                  filename.hasPrefix("ForgeFF-"),
                  filename.hasSuffix("-macOS.zip") else { continue }
            if let expectedFilename, filename != expectedFilename { continue }
            return digest
        }
        return nil
    }

    private enum UpdateError: LocalizedError {
        case invalidResponse
        case invalidChecksum
        case checksumMismatch
        case invalidBundle
        case updaterLaunchFailed

        var errorDescription: String? {
            switch self {
            case .invalidResponse: return "GitHub returned an invalid release response."
            case .invalidChecksum: return "The release checksum file is invalid."
            case .checksumMismatch: return "The downloaded release failed its SHA-256 check."
            case .invalidBundle: return "The downloaded release is not a valid ForgeFF app."
            case .updaterLaunchFailed: return "The system updater could not be started."
            }
        }
    }

    private static func releaseInfo(from release: GitHubRelease) -> ReleaseInfo? {
        let names = expectedAssetNames(for: release.tagName)
        guard let archive = release.assets.first(where: { $0.name == names[0] }),
              let checksum = release.assets.first(where: { $0.name == names[1] }),
              isOfficialReleaseAsset(archive.browserDownloadURL, tagName: release.tagName),
              isOfficialReleaseAsset(checksum.browserDownloadURL, tagName: release.tagName) else { return nil }
        return ReleaseInfo(
            tagName: release.tagName,
            version: normalizedVersion(release.tagName),
            releaseURL: release.htmlURL,
            archiveURL: archive.browserDownloadURL,
            checksumURL: checksum.browserDownloadURL
        )
    }

    private static func isOfficialReleaseAsset(_ url: URL, tagName: String) -> Bool {
        guard url.host == "github.com",
              url.path.hasPrefix("/\(owner)/\(repository)/releases/download/") else { return false }
        return url.path.contains("/releases/download/\(tagName)/")
    }

    nonisolated private static func normalizedVersion(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).drop(while: { $0 == "v" || $0 == "V" }).split(separator: "+", maxSplits: 1).first.map(String.init) ?? value
    }

    nonisolated private static func versionComponents(_ value: String) -> [Int] {
        let numbers = normalizedVersion(value).split(separator: ".").prefix(3).map { Int($0) ?? 0 }
        return Array(numbers) + Array(repeating: 0, count: max(0, 3 - numbers.count))
    }

    private static func download(url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.setValue("ForgeFF updater", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else { throw UpdateError.invalidResponse }
        return data
    }

    private static func sha256(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func runTool(_ executablePath: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdateError.invalidBundle }
    }

    private static func launchReplacementUpdater(
        newAppURL: URL,
        currentAppURL: URL,
        stagingDirectoryURL: URL
    ) throws {
        let script = """
        #!/bin/sh
        sleep 1
        /bin/rm -rf -- \(shellQuote(currentAppURL.path))
        /usr/bin/ditto \(shellQuote(newAppURL.path)) \(shellQuote(currentAppURL.path))
        /usr/bin/open \(shellQuote(currentAppURL.path))
        /bin/rm -rf -- \(shellQuote(stagingDirectoryURL.path))
        """
        let scriptURL = FileManager.default.temporaryDirectory.appendingPathComponent("ForgeFF-updater-\(UUID().uuidString).sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [scriptURL.path]
        try process.run()
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func userMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError, let description = localizedError.errorDescription {
            return description
        }
        return "Update check failed. Check your internet connection and try again."
    }
}
