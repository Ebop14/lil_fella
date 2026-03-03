import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var sampling = SamplingConfig()
    @State private var inference = InferenceConfig()
    @State private var showMemories = false
    @State private var showLicenses = false

    var body: some View {
        Form {
            Section("Sampling") {
                LabeledContent("Temperature: \(String(format: "%.2f", sampling.temperature))") {
                    Slider(value: $sampling.temperature, in: 0.0...2.0, step: 0.05)
                }

                LabeledContent("Top-K: \(sampling.topK)") {
                    Slider(value: Binding(
                        get: { Double(sampling.topK) },
                        set: { sampling.topK = Int32($0) }
                    ), in: 1...100, step: 1)
                }

                LabeledContent("Top-P: \(String(format: "%.2f", sampling.topP))") {
                    Slider(value: $sampling.topP, in: 0.0...1.0, step: 0.05)
                }

                LabeledContent("Max Tokens: \(sampling.maxTokens)") {
                    Slider(value: Binding(
                        get: { Double(sampling.maxTokens) },
                        set: { sampling.maxTokens = Int32($0) }
                    ), in: 64...4096, step: 64)
                }
            }

            Section("Inference") {
                LabeledContent("Context Length: \(inference.contextLength)") {
                    Slider(value: Binding(
                        get: { Double(inference.contextLength) },
                        set: { inference.contextLength = UInt32($0) }
                    ), in: 512...8192, step: 256)
                }

                Toggle("Flash Attention", isOn: $inference.flashAttention)
            }

            Section {
                Button("View Memories") {
                    showMemories = true
                }
            }

            Section {
                Button("Acknowledgements") {
                    showLicenses = true
                }
            }

            Section {
                Button("Unload Model", role: .destructive) {
                    Task { await appState.unloadModel() }
                }
            }
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $showMemories) {
            MemoriesView(memoryStore: appState.memoryStore)
        }
        .sheet(isPresented: $showLicenses) {
            LicensesView()
        }
    }
}

// MARK: - Memories Debug View

struct MemoriesView: View {
    let memoryStore: MemoryStore
    @State private var facts: [String] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if facts.isEmpty {
                    ContentUnavailableView(
                        "No Memories",
                        systemImage: "brain",
                        description: Text("Your buddy hasn't learned anything about you yet.")
                    )
                } else {
                    ForEach(Array(facts.enumerated()), id: \.offset) { index, fact in
                        Text(fact)
                            .swipeActions {
                                Button(role: .destructive) {
                                    Task {
                                        await memoryStore.deleteFact(at: index)
                                        facts = await memoryStore.currentFacts()
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }
            .navigationTitle("Memories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                facts = await memoryStore.load()
            }
        }
    }
}
