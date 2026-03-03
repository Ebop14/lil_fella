import Foundation

struct ModelDefinition: Identifiable, Sendable {
    let id: String
    let name: String
    let quant: String
    let sizeBytes: Int64
    let downloadURL: URL
    let sha256: String?

    static let qwen35_08b_q4km = ModelDefinition(
        id: "qwen3.5-0.8b-q4km",
        name: "Qwen 3.5 0.8B",
        quant: "Q4_K_M",
        sizeBytes: 533_000_000,
        downloadURL: URL(string: "https://huggingface.co/unsloth/Qwen3.5-0.8B-GGUF/resolve/main/Qwen3.5-0.8B-Q4_K_M.gguf")!,
        sha256: nil
    )

    static let allModels: [ModelDefinition] = [qwen35_08b_q4km]

    var fileName: String {
        "\(id).gguf"
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}
