import Foundation
import llama
import os.log

private let log = Logger(subsystem: "com.lilfella", category: "LlamaService")

// MARK: - Batch helpers (matching LibLlama.swift pattern)

private func llama_batch_clear(_ batch: inout llama_batch) {
    batch.n_tokens = 0
}

private func llama_batch_add(
    _ batch: inout llama_batch,
    _ id: llama_token,
    _ pos: llama_pos,
    _ seq_ids: [llama_seq_id],
    _ logits: Bool
) {
    let idx = Int(batch.n_tokens)
    batch.token[idx] = id
    batch.pos[idx] = pos
    batch.n_seq_id[idx] = Int32(seq_ids.count)
    for i in 0..<seq_ids.count {
        batch.seq_id[idx]![i] = seq_ids[i]
    }
    batch.logits[idx] = logits ? 1 : 0
    batch.n_tokens += 1
}

// MARK: - LlamaService

actor LlamaService {
    nonisolated(unsafe) private var model: OpaquePointer?
    nonisolated(unsafe) private var context: OpaquePointer?
    nonisolated(unsafe) private var vocab: OpaquePointer?
    nonisolated(unsafe) private var sampler: UnsafeMutablePointer<llama_sampler>?
    nonisolated(unsafe) private var batch: llama_batch?

    private var isCancelled = false
    private(set) var isLoaded = false
    private var contextLength: UInt32 = 2048
    private var batchSize: Int32 = 512

    /// The context length available for generation (accounts for prompt tokens)
    var availableContextLength: UInt32 { contextLength }

    // MARK: - Model lifecycle

    func loadModel(from url: URL, config: InferenceConfig = InferenceConfig()) throws {
        guard !isLoaded else {
            log.info("Model already loaded, skipping")
            return
        }

        log.info("Loading model from \(url.lastPathComponent)")
        llama_backend_init()

        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = config.gpuLayerCount
        log.info("GPU layers: \(config.gpuLayerCount)")

        guard let m = llama_model_load_from_file(url.path, modelParams) else {
            log.error("Failed to load model file")
            throw LlamaError.modelLoadFailed
        }
        model = m

        var ctxParams = llama_context_default_params()
        ctxParams.n_ctx = config.contextLength
        ctxParams.n_batch = UInt32(config.batchSize)
        ctxParams.n_threads = config.threadCount
        ctxParams.n_threads_batch = config.threadCount
        if config.flashAttention {
            ctxParams.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_ENABLED
        }

        log.info("Context params: n_ctx=\(config.contextLength), n_batch=\(config.batchSize), threads=\(config.threadCount), flash_attn=\(config.flashAttention)")

        guard let ctx = llama_init_from_model(m, ctxParams) else {
            log.error("Failed to create inference context")
            llama_model_free(m)
            model = nil
            throw LlamaError.contextCreationFailed
        }
        context = ctx
        vocab = llama_model_get_vocab(m)
        batch = llama_batch_init(config.batchSize, 0, 1)
        contextLength = config.contextLength
        batchSize = config.batchSize
        isLoaded = true
        log.info("Model loaded successfully")
    }

    func unloadModel() {
        guard isLoaded else { return }
        log.info("Unloading model")
        if let s = sampler { llama_sampler_free(s); sampler = nil }
        if let b = batch { llama_batch_free(b); batch = nil }
        if let ctx = context { llama_free(ctx); context = nil }
        if let m = model { llama_model_free(m); model = nil }
        vocab = nil
        isLoaded = false
        llama_backend_free()
    }

    func cancelGeneration() {
        log.info("Generation cancelled")
        isCancelled = true
    }

    /// Count tokens for a string without generating
    func tokenCount(for text: String) -> Int {
        tokenize(text, addSpecial: true, parseSpecial: true).count
    }

    // MARK: - Inference

    func generate(prompt: String, sampling: SamplingConfig = SamplingConfig()) -> AsyncStream<String> {
        AsyncStream { continuation in
            guard let context, let vocab, var batch else {
                log.error("Generate called but model not loaded (context/vocab/batch nil)")
                continuation.finish()
                return
            }

            isCancelled = false

            // Set up sampler chain: top-k → top-p → temp → dist
            let sparams = llama_sampler_chain_default_params()
            let chain = llama_sampler_chain_init(sparams)!
            llama_sampler_chain_add(chain, llama_sampler_init_top_k(sampling.topK))
            llama_sampler_chain_add(chain, llama_sampler_init_top_p(sampling.topP, 1))
            llama_sampler_chain_add(chain, llama_sampler_init_temp(sampling.temperature))
            llama_sampler_chain_add(chain, llama_sampler_init_penalties(
                64, sampling.repeatPenalty, 0.0, 0.0
            ))
            llama_sampler_chain_add(chain, llama_sampler_init_dist(sampling.seed))
            self.sampler = chain

            // Tokenize (parse_special: true for ChatML tokens)
            let tokens = tokenize(prompt, addSpecial: true, parseSpecial: true)
            guard !tokens.isEmpty else {
                log.error("Tokenization produced empty result")
                llama_sampler_free(chain)
                self.sampler = nil
                continuation.finish()
                return
            }

            log.info("Prompt tokenized: \(tokens.count) tokens, context limit: \(self.contextLength), max generation: \(sampling.maxTokens)")

            // Check if prompt exceeds context window
            let maxPromptTokens = Int(self.contextLength) - Int(sampling.maxTokens / 4) // leave room for at least some generation
            if tokens.count > Int(self.contextLength) {
                log.error("Prompt (\(tokens.count) tokens) exceeds context window (\(self.contextLength))! Aborting.")
                llama_sampler_free(chain)
                self.sampler = nil
                continuation.yield("[Context window exceeded - please clear conversation]")
                continuation.finish()
                return
            } else if tokens.count > maxPromptTokens {
                log.warning("Prompt (\(tokens.count) tokens) leaves very little room for generation (context: \(self.contextLength))")
            }

            // Prefill: process prompt tokens in batch-sized chunks
            let chunkSize = Int(self.batchSize)
            let totalChunks = (tokens.count + chunkSize - 1) / chunkSize
            log.info("Prefill: \(tokens.count) tokens in \(totalChunks) chunk(s) of up to \(chunkSize)")

            for chunkIdx in 0..<totalChunks {
                let start = chunkIdx * chunkSize
                let end = min(start + chunkSize, tokens.count)
                let isLastChunk = chunkIdx == totalChunks - 1

                llama_batch_clear(&batch)
                for i in start..<end {
                    let isLastToken = isLastChunk && (i == end - 1)
                    llama_batch_add(&batch, tokens[i], Int32(i), [0], isLastToken)
                }

                let decodeResult = llama_decode(context, batch)
                if decodeResult != 0 {
                    log.error("Prefill decode failed at chunk \(chunkIdx + 1)/\(totalChunks) with error \(decodeResult)")
                    llama_sampler_free(chain)
                    self.sampler = nil
                    continuation.finish()
                    return
                }

                if totalChunks > 1 {
                    log.debug("Prefill chunk \(chunkIdx + 1)/\(totalChunks) done (\(end - start) tokens)")
                }
            }

            log.info("Prefill complete, starting generation")

            var nCur = Int32(tokens.count)
            var decoder = TokenDecoder()
            var tokensGenerated: Int32 = 0

            // Autoregressive decode loop
            while !isCancelled && tokensGenerated < sampling.maxTokens {
                // Check we're not about to exceed context
                if nCur >= Int32(self.contextLength) {
                    log.warning("Reached context limit (\(self.contextLength)) after \(tokensGenerated) generated tokens, stopping")
                    break
                }

                let newTokenId = llama_sampler_sample(chain, context, batch.n_tokens - 1)

                if llama_vocab_is_eog(vocab, newTokenId) {
                    log.info("EOG token received after \(tokensGenerated) tokens")
                    let remaining = decoder.flush()
                    if !remaining.isEmpty {
                        continuation.yield(remaining)
                    }
                    break
                }

                let bytes = tokenToBytes(newTokenId)
                let text = decoder.decode(bytes)
                if !text.isEmpty {
                    continuation.yield(text)
                }

                // Prepare next decode step
                llama_batch_clear(&batch)
                llama_batch_add(&batch, newTokenId, nCur, [0], true)

                nCur += 1
                tokensGenerated += 1

                if llama_decode(context, batch) != 0 {
                    log.error("Decode failed at token \(tokensGenerated)")
                    break
                }
            }

            if isCancelled {
                log.info("Generation cancelled after \(tokensGenerated) tokens")
            } else if tokensGenerated >= sampling.maxTokens {
                log.info("Generation hit max tokens limit (\(sampling.maxTokens))")
            }

            // Flush any remaining bytes
            let remaining = decoder.flush()
            if !remaining.isEmpty {
                continuation.yield(remaining)
            }

            self.batch = batch
            llama_sampler_free(chain)
            self.sampler = nil
            log.info("Generation finished: \(tokensGenerated) tokens generated, total context used: \(nCur)")
            continuation.finish()
        }
    }

    func clearContext() {
        guard let context else { return }
        log.info("Clearing KV cache")
        let memory = llama_get_memory(context)
        llama_memory_clear(memory, true)
    }

    // MARK: - Tokenization

    private func tokenize(_ text: String, addSpecial: Bool, parseSpecial: Bool) -> [llama_token] {
        guard let vocab else { return [] }
        let utf8Count = text.utf8.count
        let maxTokens = utf8Count + (addSpecial ? 1 : 0) + 1
        let tokens = UnsafeMutablePointer<llama_token>.allocate(capacity: maxTokens)
        defer { tokens.deallocate() }

        let count = llama_tokenize(
            vocab, text, Int32(utf8Count),
            tokens, Int32(maxTokens),
            addSpecial, parseSpecial
        )

        guard count >= 0 else {
            log.error("Tokenization failed with error code \(count)")
            return []
        }
        return (0..<Int(count)).map { tokens[$0] }
    }

    private func tokenToBytes(_ token: llama_token) -> [UInt8] {
        guard let vocab else { return [] }
        let bufSize = 32
        let buf = UnsafeMutablePointer<CChar>.allocate(capacity: bufSize)
        defer { buf.deallocate() }

        var nBytes = llama_token_to_piece(vocab, token, buf, Int32(bufSize), 0, false)

        if nBytes < 0 {
            let needed = Int(-nBytes)
            let bigBuf = UnsafeMutablePointer<CChar>.allocate(capacity: needed)
            defer { bigBuf.deallocate() }
            nBytes = llama_token_to_piece(vocab, token, bigBuf, Int32(needed), 0, false)
            return (0..<Int(nBytes)).map { UInt8(bitPattern: bigBuf[$0]) }
        }

        return (0..<Int(nBytes)).map { UInt8(bitPattern: buf[$0]) }
    }
}

// MARK: - Errors

enum LlamaError: Error, LocalizedError {
    case modelLoadFailed
    case contextCreationFailed
    case decodeFailed

    var errorDescription: String? {
        switch self {
        case .modelLoadFailed: "Failed to load model file"
        case .contextCreationFailed: "Failed to create inference context"
        case .decodeFailed: "Token decoding failed"
        }
    }
}
