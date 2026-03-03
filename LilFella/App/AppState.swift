import Foundation
import SwiftUI
import UIKit

@Observable
@MainActor
final class AppState {
    let llamaService = LlamaService()
    let modelManager = ModelManager()
    let memoryStore = MemoryStore()
    let buddy = BuddyIdentity.defaultBuddy

    private(set) var isModelLoaded = false
    private(set) var isLoadingModel = false
    private(set) var errorMessage: String?

    var inferenceConfig = InferenceConfig()

    private static let lastModelKey = "lastLoadedModelID"

    nonisolated(unsafe) private var memoryWarningObserver: (any NSObjectProtocol)?

    init() {
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                if self.isModelLoaded {
                    await self.unloadModel()
                    self.errorMessage = "Model unloaded due to memory pressure. Please reload."
                }
            }
        }
    }

    deinit {
        if let observer = memoryWarningObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    enum ScreenState {
        case needsDownload
        case readyToLoad
        case loading
        case ready
        case error(String)
    }

    var screenState: ScreenState {
        if let error = errorMessage {
            return .error(error)
        }
        if isLoadingModel {
            return .loading
        }
        if isModelLoaded {
            return .ready
        }
        if modelManager.downloadedModels.isEmpty {
            return .needsDownload
        }
        return .readyToLoad
    }

    func loadModel(_ localModel: LocalModel) async {
        guard !isLoadingModel else { return }

        // Check available memory before loading
        if !MemoryMonitor.canLoad(modelSizeBytes: localModel.definition.sizeBytes) {
            errorMessage = "Not enough memory to load this model. Available: \(Int(MemoryMonitor.availableMemoryMB())) MB"
            return
        }

        isLoadingModel = true
        errorMessage = nil

        do {
            try await llamaService.loadModel(from: localModel.fileURL, config: inferenceConfig)
            isModelLoaded = true
            UserDefaults.standard.set(localModel.definition.id, forKey: Self.lastModelKey)
        } catch {
            errorMessage = "Failed to load model: \(error.localizedDescription)"
        }

        isLoadingModel = false
    }

    func unloadModel() async {
        await llamaService.unloadModel()
        isModelLoaded = false
    }

    func autoLoadLastModel() async {
        guard !isModelLoaded, !isLoadingModel else { return }
        guard let lastID = UserDefaults.standard.string(forKey: Self.lastModelKey),
              let localModel = modelManager.downloadedModels.first(where: { $0.definition.id == lastID }) else {
            return
        }
        await loadModel(localModel)
    }

    func clearError() {
        errorMessage = nil
    }
}
