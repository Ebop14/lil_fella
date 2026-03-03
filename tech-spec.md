# Tech Spec: Local LLM iOS App (Qwen 3.5 Small)

## Overview

A native iOS application that runs Qwen 3.5 Small models entirely on-device using llama.cpp as the inference backend. All inference is offline after the initial model download. No API keys, no server dependencies, no data leaves the device.

### Target Models

| Model | FP16 Size | Q4_K_M Size | Min iPhone RAM | Use Case |
|-------|-----------|-------------|----------------|----------|
| Qwen3.5-0.8B | ~1.6 GB | ~500–600 MB | 4 GB (iPhone 12+) | Fast responses, basic tasks |
| Qwen3.5-2B | ~4 GB | ~1.5 GB | 6 GB (iPhone 15+) | Balanced quality/speed |
| Qwen3.5-4B | ~8 GB | ~2.5–3 GB | 8 GB (iPhone 15 Pro+) | Strong reasoning, multimodal |

The 9B model is excluded from the initial target — at ~5–6 GB quantized, it exceeds the practical memory budget on all current iPhones except the 16 Pro Max under ideal conditions.

### Key Constraints

- **Memory budget:** iOS grants foreground apps roughly 2–3 GB depending on device. Model weights + KV cache + app overhead must fit within this.
- **Thermal throttling:** Sustained matrix multiplications heat the SoC. The app must handle degraded throughput gracefully.
- **Storage:** Users must opt in to downloading 500 MB–3 GB of model data. The app itself should be <20 MB.
- **No network after download:** The GGUF file contains all weights, tokenizer vocab, chat template, and special token IDs. Inference is fully self-contained.

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                    SwiftUI Layer                     │
│  ContentView ← ChatViewModel (publishes tokens)     │
│  ModelPickerView ← ModelManager (download state)    │
│  SettingsView (context length, threads, sampling)   │
├─────────────────────────────────────────────────────┤
│                  Swift Service Layer                 │
│  ChatViewModel        ModelManager                  │
│  - conversation       - download from HF Hub        │
│    history            - store in App Support/        │
│  - formats ChatML     - verify integrity            │
│  - streams tokens     - list/delete models          │
│    to UI                                            │
├─────────────────────────────────────────────────────┤
│                  Inference Engine                    │
│  LlamaService (Swift wrapper around C API)          │
│  - llama_model_load_from_file()                     │
│  - llama_context_new()                              │
│  - tokenize → decode → sample loop                  │
│  - Metal GPU offloading                             │
├─────────────────────────────────────────────────────┤
│                  llama.cpp (C/C++)                   │
│  Linked via XCFramework or SPM from source          │
│  - GGUF parser                                      │
│  - Quantized matmul kernels (ARM NEON + Metal)      │
│  - KV cache management                              │
│  - Sampling algorithms                              │
└─────────────────────────────────────────────────────┘
```

---

## Component Specifications

### 1. llama.cpp Integration

**Approach:** Start with SPM source compilation (Option A) for access to latest Qwen 3.5 support. Migrate to XCFramework (Option B) once a stable release includes full Gated DeltaNet support.

**SPM dependency (Option A):**

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/ggml-org/llama.cpp.git", branch: "master")
]
```

**XCFramework dependency (Option B):**

```swift
// Package.swift — switch to this once a release covers Qwen 3.5
.binaryTarget(
    name: "LlamaFramework",
    url: "https://github.com/ggml-org/llama.cpp/releases/download/<version>/llama-<version>-xcframework.zip",
    checksum: "<sha256>"
)
```

**Build configuration:**

- Metal GPU offloading: enabled (all layers)
- Flash attention: enabled (reduces KV cache memory by ~50%)
- NEON SIMD: enabled via compiler flags (arm64 dotprod + fp16)
- Build scheme: **Release only** for inference — Debug builds are 3–5x slower due to missing optimizations

---

### 2. LlamaService

The core Swift class that wraps llama.cpp's C API. Owns the model and context lifecycle.

**Responsibilities:**

- Load/unload GGUF models
- Manage the inference context (KV cache, batch state)
- Run the tokenize → prefill → decode → sample loop
- Expose an async streaming interface to the view model
- Handle memory pressure notifications (unload model on `didReceiveMemoryWarning`)

**Public interface:**

```swift
actor LlamaService {
    /// Load a model from a local GGUF file path.
    /// - Parameters:
    ///   - url: file URL to the .gguf in App Support
    ///   - config: inference configuration (context length, threads, GPU layers)
    func loadModel(from url: URL, config: InferenceConfig) async throws

    /// Unload the current model and free all memory.
    func unloadModel()

    /// Run inference on a formatted prompt string.
    /// Returns an AsyncStream that yields token strings as they're generated.
    func generate(prompt: String, sampling: SamplingConfig) -> AsyncStream<String>

    /// Cancel an in-progress generation.
    func cancelGeneration()

    /// Whether a model is currently loaded and ready.
    var isLoaded: Bool { get }
}
```

**Key implementation details:**

```swift
struct InferenceConfig {
    var contextLength: Int = 4096    // n_ctx — tokens of conversation history
    var batchSize: Int = 512         // n_batch — tokens processed per decode call
    var threadCount: Int = 4         // n_threads — CPU threads for non-Metal work
    var gpuLayerCount: Int = 99      // n_gpu_layers — 99 = offload everything to Metal
    var flashAttention: Bool = true  // halves KV cache memory usage
}

struct SamplingConfig {
    var temperature: Float = 0.6     // Qwen-recommended default
    var topK: Int = 20               // Qwen-recommended default
    var topP: Float = 0.95           // Qwen-recommended default
    var repeatPenalty: Float = 1.0   // increase if model loops
    var maxTokens: Int = 2048        // generation cap per response
}
```

**Inference loop (pseudocode):**

```
func generate(prompt, sampling) -> AsyncStream<String>:
    tokens = tokenize(prompt)                    // string → token IDs
    batch = create_batch(tokens)
    llama_decode(context, batch)                 // prefill: process all input tokens

    loop:
        logits = llama_get_logits(context)       // raw vocab scores
        next_token = sample(logits, sampling)    // temperature → top-k → top-p → pick

        if next_token == eos_token: break        // <|im_end|> → stop
        if token_count >= sampling.maxTokens: break

        text_piece = token_to_string(next_token) // token ID → UTF-8 bytes
        yield text_piece                         // stream to caller

        batch = create_batch([next_token])       // single-token batch
        llama_decode(context, batch)             // decode: one forward pass
```

**Memory management strategy:**

- Register for `UIApplication.didReceiveMemoryWarningNotification`. On trigger, call `unloadModel()` to free the `llama_model` and `llama_context`. This releases the mmap'd GGUF and KV cache.
- On `sceneDidEnterBackground`, optionally unload to prevent iOS from terminating the app. On `sceneWillEnterForeground`, reload. This adds a 2–5 second load time on resume but prevents hard kills.
- Track memory usage via `os_proc_available_memory()` before loading. If available memory < model file size + 500 MB (KV cache + headroom), warn the user or suggest a smaller model.

---

### 3. ModelManager

Handles downloading, storing, and managing GGUF files.

**Storage location:** `FileManager.default.urls(for: .applicationSupportDirectory)` — this directory is backed up by iCloud (if enabled), persists across app updates, and is not subject to the system's cache purging.

**Download source:** Hugging Face Hub API. Direct file URL pattern:

```
https://huggingface.co/Qwen/Qwen3.5-{size}-GGUF/resolve/main/qwen3.5-{size}-{quant}.gguf
```

Alternatively, use Unsloth's quantized variants:

```
https://huggingface.co/unsloth/Qwen3.5-{size}-GGUF/resolve/main/Qwen3.5-{size}-{quant}.gguf
```

**Public interface:**

```swift
@Observable
class ModelManager {
    /// Available models that can be downloaded.
    var availableModels: [ModelDefinition]

    /// Models already downloaded to local storage.
    var downloadedModels: [LocalModel]

    /// Active download progress (nil if no download in progress).
    var downloadProgress: DownloadProgress?

    /// Download a model from Hugging Face.
    /// Uses URLSession background configuration for resilience.
    func download(_ model: ModelDefinition) async throws

    /// Delete a downloaded model from disk.
    func delete(_ model: LocalModel) throws

    /// Verify a downloaded file's integrity (file size check + optional SHA256).
    func verify(_ model: LocalModel) -> Bool
}

struct ModelDefinition {
    let name: String              // "Qwen3.5-2B"
    let quantization: String      // "Q4_K_M"
    let sizeBytes: Int64          // expected file size for progress + verification
    let downloadURL: URL          // Hugging Face direct link
    let sha256: String?           // optional hash for integrity check
}

struct LocalModel {
    let definition: ModelDefinition
    let fileURL: URL              // path in Application Support
    let downloadDate: Date
}
```

**Download implementation notes:**

- Use `URLSessionConfiguration.background(withIdentifier:)` so downloads continue when the app is suspended. iOS wakes the app via `application(_:handleEventsForBackgroundURLSession:)` when the download completes.
- Resume support: store the `resumeData` from `urlSession(_:task:didCompleteWithError:)` if the download fails. On retry, create the task with `downloadTask(withResumeData:)` instead of starting from scratch.
- GGUF files are single large files (no multipart), so a single `URLSessionDownloadTask` is sufficient.
- Show download progress via the `URLSessionDownloadDelegate` method `urlSession(_:downloadTask:didWriteData:totalBytesWritten:totalBytesExpectedToWrite:)`.

---

### 4. ChatViewModel

Manages conversation state, formats prompts, and bridges between the UI and `LlamaService`.

**Public interface:**

```swift
@Observable
@MainActor
class ChatViewModel {
    var messages: [ChatMessage] = []
    var isGenerating: Bool = false
    var currentStreamedText: String = ""
    var tokensPerSecond: Double = 0.0

    func send(_ text: String) async
    func stopGenerating()
    func clearConversation()
}

struct ChatMessage: Identifiable {
    let id: UUID
    let role: Role          // .user, .assistant, .system
    let content: String
    let timestamp: Date

    enum Role { case user, assistant, system }
}
```

**Chat template formatting:**

The view model is responsible for converting the `messages` array into a single prompt string that matches Qwen 3.5's expected ChatML format:

```swift
func formatPrompt() -> String {
    var prompt = ""
    for message in messages {
        switch message.role {
        case .system:
            prompt += "<|im_start|>system\n\(message.content)<|im_end|>\n"
        case .user:
            prompt += "<|im_start|>user\n\(message.content)<|im_end|>\n"
        case .assistant:
            prompt += "<|im_start|>assistant\n\(message.content)<|im_end|>\n"
        }
    }
    // Open the assistant turn for the model to complete
    prompt += "<|im_start|>assistant\n"
    return prompt
}
```

**Context window management:**

The conversation history can grow beyond the model's context window (4096 tokens at our default setting). The view model must handle this by truncating older messages when the total token count approaches the limit. Strategy:

1. Always keep the system prompt (first message).
2. Always keep the most recent user message.
3. Drop the oldest user/assistant pairs until the total fits within `contextLength - maxTokens` (reserving room for the response).
4. Optionally prepend a "summary" of dropped messages, though this adds complexity.

---

### 5. SwiftUI Views

**ContentView (Chat Interface):**

- `ScrollViewReader` wrapping a `LazyVStack` of message bubbles.
- Auto-scroll to bottom as new tokens stream in.
- Text input field with send button; disabled while `isGenerating` is true.
- Stop button visible during generation (calls `stopGenerating()`).
- Tokens/second display during generation for transparency.
- Markdown rendering for assistant messages (use `MarkdownUI` library).

**ModelPickerView (Model Management):**

- List of available models with size, quantization, and estimated performance.
- Download button with progress bar for each model.
- Swipe-to-delete for downloaded models.
- Storage usage summary (total space used by models).
- Device compatibility warnings (e.g., "This model may exceed your device's memory").

**SettingsView (Inference Configuration):**

- Sliders for: context length (1024–8192), thread count (1–6), temperature (0–1.5), top-k (1–100), top-p (0.5–1.0).
- Toggle for flash attention.
- Estimated memory usage display that updates as settings change.
- Reset to defaults button.

---

## Data Flow

### Inference Request Lifecycle

```
User taps Send
       │
       ▼
ChatViewModel.send()
       │
       ├── Append user message to messages[]
       ├── Format full conversation as ChatML string
       ├── Check token count vs context window, truncate if needed
       │
       ▼
LlamaService.generate(prompt, sampling)
       │
       ├── Tokenize prompt string → [Int32] token IDs
       ├── Create llama_batch with all input tokens
       ├── llama_decode() — prefill phase (parallel, fast)
       │       └── All transformer layers execute on Metal GPU
       │       └── KV cache populated for all input positions
       │
       ├── Loop: autoregressive decoding
       │     ├── llama_get_logits() → [Float] vocab scores
       │     ├── Apply temperature scaling
       │     ├── Apply top-k filtering
       │     ├── Apply top-p (nucleus) filtering
       │     ├── Sample token from distribution
       │     ├── Check: is this the EOS token (<|im_end|>)?
       │     │     └── Yes → break loop
       │     ├── Convert token ID → UTF-8 string piece
       │     ├── Yield string piece via AsyncStream
       │     ├── Create single-token batch
       │     └── llama_decode() — one forward pass for new token
       │
       ▼
AsyncStream yields back to ChatViewModel
       │
       ├── Append each piece to currentStreamedText (on @MainActor)
       ├── Update tokensPerSecond
       │
       ▼
SwiftUI re-renders message bubble with growing text
       │
       ▼
On stream completion:
       ├── Append final assistant message to messages[]
       ├── Clear currentStreamedText
       └── Set isGenerating = false
```

### Model Download Lifecycle

```
User taps Download on ModelPickerView
       │
       ▼
ModelManager.download(modelDefinition)
       │
       ├── Create background URLSession
       ├── Create downloadTask with Hugging Face URL
       ├── Publish progress updates via downloadProgress
       │
       ▼
URLSessionDownloadDelegate callbacks
       │
       ├── didWriteData → update progress (bytes written / total)
       ├── didFinishDownloading →
       │     ├── Move temp file to Application Support/Models/
       │     ├── Verify file size matches expected
       │     ├── (Optional) Verify SHA256 hash
       │     ├── Add to downloadedModels[]
       │     └── Clear downloadProgress
       │
       ▼
Model appears in ModelPickerView as available for loading
```

---

## Memory Budget Analysis

Estimated memory usage per model at Q4_K_M quantization with 4096 context and flash attention enabled:

| Component | 0.8B | 2B | 4B |
|-----------|------|----|----|
| Model weights (mmap'd) | ~550 MB | ~1.5 GB | ~2.8 GB |
| KV cache (flash attn) | ~80 MB | ~150 MB | ~250 MB |
| Tokenizer + scratch buffers | ~50 MB | ~50 MB | ~50 MB |
| App + OS overhead | ~300 MB | ~300 MB | ~300 MB |
| **Total** | **~980 MB** | **~2.0 GB** | **~3.4 GB** |
| Typical iOS budget | 2.5–3 GB | 2.5–3 GB | 3–4 GB (Pro) |
| **Headroom** | ~1.5+ GB | ~0.5–1 GB | ~0.5 GB (Pro only) |

Notes:

- `mmap` means the OS can page out unused weight pages under memory pressure, but this causes inference stalls when pages need to be faulted back in from flash storage. In practice, the "active" working set during a forward pass is smaller than the full file, but you want the full file resident for consistent speed.
- Flash attention roughly halves KV cache memory by not storing the full attention matrix, recomputing it on the fly instead. This trades compute for memory — a good tradeoff on memory-constrained phones.
- The 4B model is viable only on Pro/Pro Max devices with 8 GB RAM. The app should detect device class and warn accordingly.

---

## Device Compatibility

| iPhone | RAM | Max Recommended Model | Notes |
|--------|-----|-----------------------|-------|
| iPhone 12/13/14 | 4–6 GB | 0.8B Q4 | Limited headroom, may throttle |
| iPhone 15 | 6 GB | 2B Q4 | Comfortable for 2B |
| iPhone 15 Pro/Pro Max | 8 GB | 4B Q4 | A17 Pro Metal GPU, best perf |
| iPhone 16 | 8 GB | 4B Q4 | A18, good performance |
| iPhone 16 Pro/Pro Max | 8 GB | 4B Q4 | A18 Pro, best perf tier |

Detection via `ProcessInfo.processInfo.physicalMemory` and `os_proc_available_memory()` at runtime. The app should suggest the largest model that fits comfortably, not the largest that theoretically fits.

---

## Project Structure

```
QwenLocal/
├── Package.swift                          # llama.cpp dependency
├── QwenLocal/
│   ├── App/
│   │   ├── QwenLocalApp.swift             # @main, scene setup
│   │   └── AppDelegate.swift              # background URL session handling
│   ├── Services/
│   │   ├── LlamaService.swift             # C API wrapper (actor)
│   │   ├── LlamaBridge.h                  # Bridging header for llama.h
│   │   └── TokenDecoder.swift             # UTF-8 byte buffer for partial tokens
│   ├── Models/
│   │   ├── ChatMessage.swift
│   │   ├── ModelDefinition.swift
│   │   ├── InferenceConfig.swift
│   │   └── SamplingConfig.swift
│   ├── ViewModels/
│   │   ├── ChatViewModel.swift
│   │   └── ModelManager.swift
│   ├── Views/
│   │   ├── ContentView.swift              # Chat interface
│   │   ├── MessageBubbleView.swift
│   │   ├── ModelPickerView.swift
│   │   ├── SettingsView.swift
│   │   └── DownloadProgressView.swift
│   └── Utilities/
│       ├── MemoryMonitor.swift            # os_proc_available_memory tracking
│       ├── DeviceCapability.swift         # RAM detection, model recommendations
│       └── ChatMLFormatter.swift          # Conversation → ChatML prompt string
└── Tests/
    ├── ChatMLFormatterTests.swift
    ├── TokenDecoderTests.swift
    └── ModelManagerTests.swift
```

---

## Token Decoding Edge Case

Qwen 3.5 uses a 248K-token vocabulary. Some tokens map to partial UTF-8 byte sequences — for example, a multi-byte emoji might be split across two tokens. Naively converting each token to a string will produce replacement characters (�) for these partial sequences.

**Solution:** `TokenDecoder` maintains a byte buffer. Each token's raw bytes are appended to the buffer. After each append, attempt to decode the buffer as UTF-8 from the front. Yield any complete characters and keep the remaining incomplete bytes in the buffer for the next token.

```swift
class TokenDecoder {
    private var buffer: [UInt8] = []

    func decode(tokenBytes: [UInt8]) -> String {
        buffer.append(contentsOf: tokenBytes)
        // Try to decode as much valid UTF-8 as possible from the front
        // Return the decoded string, keep incomplete trailing bytes
    }
}
```

---

## Open Questions

1. **Thinking mode:** Qwen 3.5 Small models disable thinking by default but support it via `<think>` tags. Should the app expose a toggle for extended reasoning (longer responses, higher quality, more compute)?
2. **Multimodal input:** The 4B and 9B models support native vision (image + video). Should v1 include image input, or defer to v2? This requires integrating the vision encoder path in llama.cpp, which adds complexity.
3. **Conversation persistence:** Should chats be saved to disk (JSON files, SwiftData, or Core Data)? This is straightforward but adds a data layer.
4. **Multiple conversations:** Support for multiple chat threads, or a single active conversation?
5. **System prompt customization:** Allow users to edit the system prompt, or hardcode a sensible default?
6. **Model updates:** How to handle new quantizations or model versions — manual re-download, or a lightweight update check against the HF API?
