import SwiftUI

struct ModelPickerView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationStack {
            List {
                Section("Available Models") {
                    ForEach(appState.modelManager.availableModels) { model in
                        modelRow(model)
                    }
                }

                if !appState.modelManager.downloadedModels.isEmpty {
                    Section("Downloaded") {
                        ForEach(appState.modelManager.downloadedModels) { local in
                            downloadedRow(local)
                        }
                    }
                }
            }
            .navigationTitle("Models")
        }
    }

    @ViewBuilder
    private func modelRow(_ model: ModelDefinition) -> some View {
        let isDownloaded = appState.modelManager.localModel(for: model) != nil
        let isDownloading = appState.modelManager.currentProgress?.model.id == model.id

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(model.name)
                    .font(.headline)
                Spacer()
                Text(model.quant)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.fill.tertiary, in: Capsule())
            }

            Text(model.formattedSize)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if isDownloading, let progress = appState.modelManager.currentProgress {
                DownloadProgressView(progress: progress) {
                    appState.modelManager.cancelDownload()
                }
            } else if !isDownloaded {
                Button("Download") {
                    appState.modelManager.download(model)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            } else {
                Label("Downloaded", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 4)

        if let error = appState.modelManager.downloadError {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private func downloadedRow(_ local: LocalModel) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(local.definition.name)
                    .font(.headline)
                Text("Downloaded \(local.downloadDate.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if appState.isLoadingModel {
                ProgressView()
            } else {
                Button("Load") {
                    Task { await appState.loadModel(local) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                appState.modelManager.delete(local)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
