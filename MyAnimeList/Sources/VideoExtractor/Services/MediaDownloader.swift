import Foundation
import Combine

final class DownloadDirectoryStore: ObservableObject {
    nonisolated(unsafe) static let shared = DownloadDirectoryStore()

    @Published private(set) var directoryURL: URL?
    @Published private(set) var displayName = "应用内 Downloads"
    @Published private(set) var isCustomDirectory = false

    private let bookmarkKey = "videoExtractor.downloadDirectoryBookmark"

    init() {
        loadSavedDirectory()
    }

    var activeDirectory: URL {
        directoryURL ?? MediaDownloader.defaultDownloadsDirectory
    }

    func set(_ url: URL) {
        directoryURL = url
        isCustomDirectory = true
        displayName = url.lastPathComponent

        if let bookmark = try? url.bookmarkData(
            options: [.minimalBookmark],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
        } else {
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
        }
    }

    func reset() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        directoryURL = nil
        isCustomDirectory = false
        displayName = "应用内 Downloads"
    }

    private func loadSavedDirectory() {
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else {
            return
        }

        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            directoryURL = url
            isCustomDirectory = true
            displayName = url.lastPathComponent
        } catch {
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
            directoryURL = nil
            isCustomDirectory = false
            displayName = "应用内 Downloads"
        }
    }
}

struct DownloadTask: Identifiable {
    var id: UUID { candidate.id }
    let candidate: MediaCandidate
    var progress: Double
    var status: String
}

final class DownloadManager: NSObject, ObservableObject {
    nonisolated(unsafe) static let shared = DownloadManager()

    @Published private(set) var tasks: [UUID: DownloadTask] = [:]

    private var continuations: [UUID: CheckedContinuation<URL, Error>] = [:]
    private var taskIdentifiers: [Int: UUID] = [:]
    private var finishedURLs: [UUID: URL] = [:]
    private var taskErrors: [UUID: Error] = [:]

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 600
        return URLSession(
            configuration: configuration,
            delegate: self,
            delegateQueue: OperationQueue.main
        )
    }()

    func isDownloading(_ candidate: MediaCandidate) -> Bool {
        tasks[candidate.id] != nil
    }

    func progress(for candidate: MediaCandidate) -> Double {
        tasks[candidate.id]?.progress ?? 0
    }

    func status(for candidate: MediaCandidate) -> String? {
        tasks[candidate.id]?.status
    }

    func download(_ candidate: MediaCandidate) async throws -> URL {
        guard tasks[candidate.id] == nil else {
            throw NSError(
                domain: "VideoExtractor",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "该文件已在下载中。"]
            )
        }

        tasks[candidate.id] = DownloadTask(
            candidate: candidate,
            progress: 0,
            status: "准备下载..."
        )

        return try await withCheckedThrowingContinuation { continuation in
            continuations[candidate.id] = continuation

            var request = URLRequest(url: candidate.url)
            request.timeoutInterval = 120
            request.setValue(
                VideoExtractorEngine.userAgent,
                forHTTPHeaderField: "User-Agent"
            )

            let downloadTask = session.downloadTask(with: request)
            taskIdentifiers[downloadTask.taskIdentifier] = candidate.id
            downloadTask.resume()
        }
    }
}

extension DownloadManager: URLSessionDownloadDelegate {
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let id = taskIdentifiers[downloadTask.taskIdentifier],
              var task = tasks[id] else {
            return
        }

        let fraction: Double
        if totalBytesExpectedToWrite > 0 {
            fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        } else {
            fraction = 0
        }

        task.progress = min(max(fraction, 0), 1)
        task.status = String(format: "下载中 %.0f%%", fraction * 100)
        tasks[id] = task
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let id = taskIdentifiers[downloadTask.taskIdentifier],
              let task = tasks[id] else {
            return
        }

        if var task = tasks[id] {
            task.status = "正在保存..."
            tasks[id] = task
        }

        do {
            let destination = try MediaDownloader.saveDownloadedFile(
                from: location,
                candidate: task.candidate
            )
            finishedURLs[id] = destination
        } catch {
            taskErrors[id] = error
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let id = taskIdentifiers[task.taskIdentifier] else {
            return
        }

        defer {
            taskIdentifiers.removeValue(forKey: task.taskIdentifier)
            continuations.removeValue(forKey: id)
            tasks.removeValue(forKey: id)
            finishedURLs.removeValue(forKey: id)
            taskErrors.removeValue(forKey: id)
        }

        guard let continuation = continuations[id] else {
            return
        }

        if let error = error ?? taskErrors[id] {
            continuation.resume(throwing: error)
        } else if let destination = finishedURLs[id] {
            continuation.resume(returning: destination)
        } else {
            continuation.resume(
                throwing: NSError(
                    domain: "VideoExtractor",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "下载失败，请稍后重试。"]
                )
            )
        }
    }
}

enum MediaDownloader {
    static var defaultDownloadsDirectory: URL {
        let documents = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]
        return documents.appendingPathComponent("Downloads", isDirectory: true)
    }

    static var downloadsDirectory: URL {
        DownloadDirectoryStore.shared.activeDirectory
    }

    static func withActiveDirectory<T>(
        _ body: (URL) throws -> T
    ) throws -> T {
        let store = DownloadDirectoryStore.shared
        let directory = store.activeDirectory
        let didStart = store.isCustomDirectory
            ? directory.startAccessingSecurityScopedResource()
            : false

        defer {
            if didStart {
                directory.stopAccessingSecurityScopedResource()
            }
        }

        return try body(directory)
    }

    static func destinationURL(
        for candidate: MediaCandidate,
        directory: URL = downloadsDirectory
    ) -> URL {
        let safeTitle = sanitizedFilename(candidate.displayTitle)
        let suffixData = candidate.url.absoluteString.data(using: .utf8)
        let suffix = suffixData.flatMap {
            String($0.base64EncodedString().prefix(6))
        } ?? ""
        let fileName = "\(safeTitle)-\(suffix).\(candidate.fileExtension)"
        return directory.appendingPathComponent(fileName)
    }

    static func saveDownloadedFile(
        from temporaryURL: URL,
        candidate: MediaCandidate
    ) throws -> URL {
        try withActiveDirectory { directory in
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )

            let destination = destinationURL(for: candidate, directory: directory)
            if FileManager.default.fileExists(atPath: destination.path) {
                try? FileManager.default.removeItem(at: destination)
            }

            try FileManager.default.moveItem(at: temporaryURL, to: destination)
            return destination
        }
    }

    static func savedFiles() -> [URL] {
        (try? withActiveDirectory { directory in
            let files = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )

            return files.sorted { first, second in
                let firstDate = (try? first.resourceValues(
                    forKeys: [.contentModificationDateKey]
                ).contentModificationDate) ?? .distantPast
                let secondDate = (try? second.resourceValues(
                    forKeys: [.contentModificationDateKey]
                ).contentModificationDate) ?? .distantPast
                return firstDate > secondDate
            }
        }) ?? []
    }

    static func delete(_ url: URL) {
        try? withActiveDirectory { directory in
            let isInside = url.path.hasPrefix(directory.path)
            guard isInside else { return }
            try FileManager.default.removeItem(at: url)
        }
    }

    private static func sanitizedFilename(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let components = value.components(separatedBy: invalid)
        let joined = components.joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? "media" : joined
    }
}
