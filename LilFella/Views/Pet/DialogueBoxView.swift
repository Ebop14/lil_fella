import SwiftUI

struct DialogueBoxView: View {
    @Bindable var viewModel: ChatViewModel
    let screenSize: CGSize
    var onNewChat: (() -> Void)?
    @FocusState private var isInputFocused: Bool

    @State private var isInputMode = false
    @State private var dotCount = 0

    private let dotTimer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    // Dynamic sizing based on screen
    private var borderOuter: CGFloat { screenSize.width * 0.008 }
    private var borderInner: CGFloat { screenSize.width * 0.005 }
    private var cornerRadius: CGFloat { screenSize.width * 0.015 }
    private var contentPadH: CGFloat { screenSize.width * 0.04 }
    private var contentPadV: CGFloat { screenSize.height * 0.012 }
    private var bodyFontSize: CGFloat { screenSize.width * 0.04 }
    private var labelFontSize: CGFloat { screenSize.width * 0.03 }

    var body: some View {
        VStack(spacing: 0) {
            // Nameplate tab
            nameplate

            // Main box
            ZStack(alignment: .bottom) {
                // Double border
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(PetPalette.borderOuter)
                RoundedRectangle(cornerRadius: cornerRadius * 0.7)
                    .fill(PetPalette.borderInner)
                    .padding(borderOuter)
                RoundedRectangle(cornerRadius: cornerRadius * 0.5)
                    .fill(PetPalette.boxFill)
                    .padding(borderOuter + borderInner)

                // Always show conversation or welcome
                VStack(spacing: 0) {
                    displayContent
                        .padding(.horizontal, contentPadH)
                        .padding(.top, contentPadV)
                        .padding(.bottom, isInputMode ? 0 : contentPadV)

                    // Input bar at bottom when active
                    if isInputMode {
                        inputBar
                            .padding(.horizontal, contentPadH)
                            .padding(.bottom, contentPadV)
                    }
                }
            }
        }
    }

    // MARK: - Nameplate

    private var nameplateFontSize: CGFloat { screenSize.width * 0.038 }

    private var nameplate: some View {
        HStack {
            nameplatePill(nameplateText)
            Spacer()
            if let onNewChat {
                Button(action: onNewChat) {
                    nameplatePill("New")
                }
            }
        }
        .padding(.leading, contentPadH)
        .padding(.trailing, contentPadH)
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
            .offset(y: screenSize.height * 0.007)
    }

    private var nameplateText: String {
        isInputMode ? "You" : "Lil Fella"
    }

    // MARK: - Display Content

    @ViewBuilder
    private var displayContent: some View {
        if viewModel.messages.isEmpty && !viewModel.isGenerating {
            welcomeText
        } else {
            conversationScroll
        }
    }

    private var conversationScroll: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .topTrailing) {
                ScrollView {
                    VStack(alignment: .leading, spacing: screenSize.height * 0.008) {
                        ForEach(viewModel.messages) { message in
                            messageLine(message)
                                .id(message.id)
                        }

                        // Currently streaming or thinking
                        if viewModel.isGenerating {
                            if viewModel.currentStreamedText.isEmpty {
                                thinkingDots
                                    .id("streaming")
                            } else {
                                Text(viewModel.currentStreamedText)
                                    .font(.system(size: bodyFontSize, weight: .regular, design: .monospaced))
                                    .foregroundStyle(PetPalette.textColor)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id("streaming")
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: viewModel.currentStreamedText) { _, _ in
                    proxy.scrollTo("streaming", anchor: .bottom)
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    if let last = viewModel.messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }

                // Scroll arrows
                if viewModel.messages.count > 1 {
                    VStack(spacing: screenSize.height * 0.005) {
                        Button {
                            withAnimation {
                                if let first = viewModel.messages.first {
                                    proxy.scrollTo(first.id, anchor: .top)
                                }
                            }
                        } label: {
                            Image(systemName: "chevron.up")
                                .font(.system(size: bodyFontSize * 0.8, weight: .bold))
                                .foregroundStyle(PetPalette.borderOuter)
                        }

                        Button {
                            withAnimation {
                                if let last = viewModel.messages.last {
                                    proxy.scrollTo(last.id, anchor: .bottom)
                                }
                            }
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: bodyFontSize * 0.8, weight: .bold))
                                .foregroundStyle(PetPalette.borderOuter)
                        }
                    }
                    .padding(screenSize.width * 0.01)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if viewModel.isGenerating {
                viewModel.stopGenerating()
            } else if !isInputMode {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isInputMode = true
                }
                isInputFocused = true
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

    private var welcomeText: some View {
        Text("* Tap here to talk *")
            .font(.system(size: bodyFontSize, weight: .regular, design: .monospaced))
            .foregroundStyle(PetPalette.textColor.opacity(0.6))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isInputMode = true
                }
                isInputFocused = true
            }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: screenSize.width * 0.02) {
            TextField("Say something...", text: $viewModel.inputText, axis: .vertical)
                .font(.system(size: bodyFontSize, weight: .regular, design: .monospaced))
                .foregroundStyle(PetPalette.textColor)
                .tint(PetPalette.borderOuter)
                .focused($isInputFocused)
                .lineLimit(1...3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onSubmit {
                    sendMessage()
                }

            Button(action: sendMessage) {
                PixelSendArrow(size: screenSize.width * 0.08)
            }
            .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .onChange(of: isInputFocused) { _, focused in
            if !focused {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isInputMode = false
                }
            }
        }
    }

    private func sendMessage() {
        guard !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isInputFocused = false
        isInputMode = false
        viewModel.send()
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

