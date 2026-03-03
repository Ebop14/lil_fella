import SwiftUI

struct DownloadProgressView: View {
    let progress: DownloadProgress
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: progress.fractionCompleted)
                .tint(.blue)

            HStack {
                Text(progress.formattedProgress)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(Int(progress.fractionCompleted * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Cancel", role: .cancel) {
                    onCancel()
                }
                .font(.caption)
            }
        }
    }
}
