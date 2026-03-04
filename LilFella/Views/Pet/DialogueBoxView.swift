import SwiftUI

// MARK: - Conversation Display Box (top section)

struct ConversationBoxView: View {
    @Bindable var viewModel: ChatViewModel
    let screenSize: CGSize

    @State private var dotCount = 0

    private let dotTimer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    // Dynamic sizing based on screen
    private var borderOuter: CGFloat { screenSize.width * 0.008 }
    private var borderInner: CGFloat { screenSize.width * 0.005 }
    private var cornerRadius: CGFloat { screenSize.width * 0.015 }
    private var contentPadH: CGFloat { screenSize.width * 0.04 }
    private var contentPadV: CGFloat { screenSize.height * 0.012 }
    private var bodyFontSize: CGFloat { screenSize.width * 0.04 }
    private var nameplateFontSize: CGFloat { screenSize.width * 0.038 }

    var body: some View {
        VStack(spacing: screenSize.height * 0.008) {
            // Nameplate tab
            HStack {
                nameplatePill("Lil Fella")
                Spacer()
            }
            .padding(.horizontal, contentPadH)

            // Main box
            ZStack {
                // Double border
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(PetPalette.borderOuter)
                RoundedRectangle(cornerRadius: cornerRadius * 0.7)
                    .fill(PetPalette.borderInner)
                    .padding(borderOuter)
                RoundedRectangle(cornerRadius: cornerRadius * 0.5)
                    .fill(PetPalette.boxFill)
                    .padding(borderOuter + borderInner)

                // Conversation content
                if !viewModel.messages.isEmpty || viewModel.isGenerating {
                    conversationScroll
                        .padding(.horizontal, contentPadH)
                        .padding(.vertical, contentPadV)
                } else {
                    Text("...")
                        .font(.system(size: bodyFontSize, weight: .regular, design: .monospaced))
                        .foregroundStyle(PetPalette.textColor.opacity(0.4))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private func nameplatePill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: nameplateFontSize, weight: .bold, design: .monospaced))
            .foregroundStyle(PetPalette.borderOuter)
            .padding(.horizontal, screenSize.width * 0.03)
            .padding(.vertical, screenSize.height * 0.004)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius * 0.7)
                    .fill(PetPalette.nameplateBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius * 0.7)
                            .stroke(PetPalette.borderOuter, lineWidth: borderOuter * 0.7)
                    )
            )
    }

    // MARK: - Conversation Scroll

    private var conversationScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(viewModel.messages) { message in
                        messageLine(message)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, screenSize.height * 0.006)
                            .id(message.id)
                    }

                    if viewModel.isGenerating {
                        if viewModel.currentStreamedText.isEmpty {
                            thinkingDots
                                .padding(.vertical, screenSize.height * 0.006)
                                .id("streaming")
                        } else {
                            Text(viewModel.currentStreamedText)
                                .font(.system(size: bodyFontSize, weight: .regular, design: .monospaced))
                                .foregroundStyle(PetPalette.textColor)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, screenSize.height * 0.006)
                                .id("streaming")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollDismissesKeyboard(.never)
            .onChange(of: viewModel.currentStreamedText) { _, _ in
                proxy.scrollTo("streaming", anchor: .bottom)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                if let last = viewModel.messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if viewModel.isGenerating {
                viewModel.stopGenerating()
            }
        }
    }

    private func messageLine(_ message: ChatMessage) -> some View {
        Group {
            if message.role == .system && message.content.hasPrefix("Remembered:") {
                HStack(spacing: screenSize.width * 0.01) {
                    Text("*")
                        .font(.system(size: bodyFontSize * 0.8, weight: .bold, design: .monospaced))
                        .foregroundStyle(PetPalette.bodyMain)
                    Text(message.content)
                        .font(.system(size: bodyFontSize * 0.8, weight: .medium, design: .monospaced))
                        .foregroundStyle(PetPalette.bodyMain)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            } else if message.role == .system {
                Text(message.content)
                    .font(.system(size: bodyFontSize * 0.8, weight: .medium, design: .monospaced))
                    .italic()
                    .foregroundStyle(PetPalette.dimText)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                HStack(alignment: .top, spacing: screenSize.width * 0.015) {
                    Text(message.role == .user ? ">" : " ")
                        .font(.system(size: bodyFontSize, weight: .bold, design: .monospaced))
                        .foregroundStyle(message.role == .user ? PetPalette.borderOuter : PetPalette.textColor)

                    Text(message.content)
                        .font(.system(size: bodyFontSize, weight: .regular, design: .monospaced))
                        .foregroundStyle(message.role == .user ? PetPalette.dimText : PetPalette.textColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var thinkingDots: some View {
        Text(String(repeating: ".", count: dotCount + 1))
            .font(.system(size: bodyFontSize * 1.1, weight: .medium, design: .monospaced))
            .foregroundStyle(PetPalette.textColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onReceive(dotTimer) { _ in
                dotCount = (dotCount + 1) % 3
            }
    }
}

// MARK: - Input Bar (bottom section, above keyboard)

struct InputBarView: View {
    @Bindable var viewModel: ChatViewModel
    let screenSize: CGSize
    var onNewChat: (() -> Void)?
    @FocusState.Binding var isInputFocused: Bool

    private var bodyFontSize: CGFloat { screenSize.width * 0.04 }
    private var borderWidth: CGFloat { screenSize.width * 0.005 }

    var body: some View {
        HStack(alignment: .bottom, spacing: screenSize.width * 0.02) {
            // New Chat button
            if let onNewChat {
                Button(action: onNewChat) {
                    Text("New")
                        .font(.system(size: bodyFontSize * 0.8, weight: .bold, design: .monospaced))
                        .foregroundStyle(PetPalette.borderOuter)
                        .padding(.horizontal, screenSize.width * 0.02)
                        .padding(.vertical, screenSize.height * 0.005)
                        .background(
                            Rectangle()
                                .fill(PetPalette.boxFill)
                                .overlay(
                                    Rectangle()
                                        .stroke(PetPalette.borderOuter, lineWidth: borderWidth)
                                )
                        )
                }
            }

            // Text field
            TextField("Say something...", text: $viewModel.inputText, axis: .vertical)
                .font(.system(size: bodyFontSize, weight: .regular, design: .monospaced))
                .foregroundStyle(PetPalette.textColor)
                .tint(PetPalette.borderOuter)
                .focused($isInputFocused)
                .lineLimit(1...3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, screenSize.width * 0.03)
                .padding(.vertical, screenSize.height * 0.008)
                .background(
                    Rectangle()
                        .fill(PetPalette.boxFill)
                        .overlay(
                            Rectangle()
                                .stroke(PetPalette.borderOuter, lineWidth: borderWidth)
                        )
                )
                .onSubmit {
                    sendMessage()
                }

            // Send button
            Button(action: sendMessage) {
                PixelSendArrow(size: screenSize.width * 0.075)
            }
            .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func sendMessage() {
        guard !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        viewModel.send()
        isInputFocused = true
    }
}

// MARK: - Pixel Send Arrow

private struct PixelSendArrow: View {
    let size: CGFloat

    // 7x7 right-pointing arrow
    private let pixels: [[Bool]] = [
        [false, false, false, true,  false, false, false],
        [false, false, false, true,  true,  false, false],
        [true,  true,  true,  true,  true,  true,  false],
        [true,  true,  true,  true,  true,  true,  true ],
        [true,  true,  true,  true,  true,  true,  false],
        [false, false, false, true,  true,  false, false],
        [false, false, false, true,  false, false, false],
    ]

    var body: some View {
        Canvas { context, _ in
            let px = size / 9 // 7 pixels + 1px padding each side
            for (y, row) in pixels.enumerated() {
                for (x, on) in row.enumerated() {
                    guard on else { continue }
                    let rect = CGRect(
                        x: px + CGFloat(x) * px,
                        y: px + CGFloat(y) * px,
                        width: px,
                        height: px
                    )
                    context.fill(Path(rect), with: .color(PetPalette.boxFill))
                }
            }
        }
        .frame(width: size, height: size)
        .background(
            RoundedRectangle(cornerRadius: size * 0.15)
                .fill(PetPalette.borderOuter)
        )
    }
}
