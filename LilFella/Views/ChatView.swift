import SwiftUI

struct ChatView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel: ChatViewModel?

    var body: some View {
        NavigationStack {
            if let viewModel {
                chatContent(viewModel)
                    .navigationTitle("Lil Fella")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                viewModel.clearConversation()
                            } label: {
                                Image(systemName: "trash")
                            }
                            .disabled(viewModel.messages.isEmpty && !viewModel.isGenerating)
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            NavigationLink {
                                SettingsView()
                            } label: {
                                Image(systemName: "gear")
                            }
                        }
                    }
            }
        }
        .task {
            let vm = ChatViewModel(
                llamaService: appState.llamaService,
                memoryStore: appState.memoryStore,
                buddy: appState.buddy
            )
            await vm.loadMemories()
            viewModel = vm
        }
    }

    @ViewBuilder
    private func chatContent(_ vm: ChatViewModel) -> some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(vm.messages) { message in
                            MessageBubbleView(message: message)
                                .id(message.id)
                        }

                        // Streaming message
                        if vm.isGenerating && !vm.currentStreamedText.isEmpty {
                            MessageBubbleView(
                                message: ChatMessage(role: .assistant, content: vm.currentStreamedText)
                            )
                            .id("streaming")
                        }
                    }
                    .padding()
                }
                .onChange(of: vm.currentStreamedText) {
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo("streaming", anchor: .bottom)
                    }
                }
                .onChange(of: vm.messages.count) {
                    if let last = vm.messages.last {
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            // Token/s indicator
            if vm.isGenerating && vm.tokensPerSecond > 0 {
                Text(String(format: "%.1f tok/s", vm.tokensPerSecond))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
            }

            // Input bar
            inputBar(vm)
        }
    }

    private func inputBar(_ vm: ChatViewModel) -> some View {
        HStack(spacing: 12) {
            @Bindable var vm = vm
            TextField("Message...", text: $vm.inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 20))
                .onSubmit {
                    vm.send()
                }

            if vm.isGenerating {
                Button {
                    vm.stopGenerating()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.red)
                }
            } else {
                Button {
                    vm.send()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(vm.inputText.trimmingCharacters(in: .whitespaces).isEmpty ? .gray : .blue)
                }
                .disabled(vm.inputText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
