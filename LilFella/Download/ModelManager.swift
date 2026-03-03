import Foundation

@Observable
@MainActor
final class ModelManager: NSObject, Sendable {
    let availableModels: [ModelDefinition] = ModelDefinition.allModels
    private(set) var downloadedModels: [LocalModel] = []
    private(set) var currentProgress: DownloadProgress?
    private(set) var downloadError: String?

    private var downloadTask: URLSessionDownloadTask?
    private var activeModel: ModelDefinition?
    private var session: URLSession?

    private static var modelsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("LilFella/Models", isDirectory: true)
    }

    override init() {
        super.init()
        scanDownloadedModels()
    }

    func scanDownloadedModels() {
        let dir = Self.modelsDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey]) else {
            downloadedModels = []
            return
        }

        downloadedModels = availableModels.compactMap { definition in
            let fileURL = dir.appendingPathComponent(definition.fileName)
            guard files.contains(where: { $0.lastPathComponent == definition.fileName }) else { return nil }
            let date = (try? fileURL.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
            return LocalModel(definition: definition, fileURL: fileURL, downloadDate: date)
        }
    }

    func download(_ model: ModelDefinition) {
        guard downloadTask == nil else { return }

        downloadError = nil
        activeModel = model

        let config = URLSessionConfiguration.default
        session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        let task = session!.downloadTask(with: model.downloadURL)
        downloadTask = task
        currentProgress = DownloadProgress(model: model, bytesWritten: 0, totalBytes: model.sizeBytes)
        task.resume()
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        activeModel = nil
        currentProgress = nil
        session?.invalidateAndCancel()
        session = nil
    }

    func delete(_ model: LocalModel) {
        try? FileManager.default.removeItem(at: model.fileURL)
        scanDownloadedModels()
    }

    func localModel(for definition: ModelDefinition) -> LocalModel? {
        downloadedModels.first { $0.definition.id == definition.id }
    }
}

// MARK: - URLSessionDownloadDelegate

extension ModelManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        MainActor.assumeIsolated {
            guard let model = activeModel else { return }
            let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : model.sizeBytes
            currentProgress = DownloadProgress(
                model: model,
                bytesWritten: totalBytesWritten,
                totalBytes: total
            )
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        MainActor.assumeIsolated {
            guard let model = activeModel else { return }

            let dir = Self.modelsDirectory
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let dest = dir.appendingPathComponent(model.fileName)

            do {
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.moveItem(at: location, to: dest)
                scanDownloadedModels()
            } catch {
                downloadError = "Failed to save model: \(error.localizedDescription)"
            }

            self.downloadTask = nil
            self.activeModel = nil
            self.currentProgress = nil
            self.session?.finishTasksAndInvalidate()
            self.session = nil
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        MainActor.assumeIsolated {
            if let error, (error as NSError).code != NSURLErrorCancelled {
                downloadError = "Download failed: \(error.localizedDescription)"
            }
            self.downloadTask = nil
            self.activeModel = nil
            self.currentProgress = nil
            self.session?.finishTasksAndInvalidate()
            self.session = nil
        }
    }
}
