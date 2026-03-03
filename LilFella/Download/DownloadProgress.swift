import Foundation

struct DownloadProgress: Sendable {
    let model: ModelDefinition
    let bytesWritten: Int64
    let totalBytes: Int64

    var fractionCompleted: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(bytesWritten) / Double(totalBytes)
    }

    var formattedProgress: String {
        let written = ByteCountFormatter.string(fromByteCount: bytesWritten, countStyle: .file)
        let total = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        return "\(written) / \(total)"
    }
}
