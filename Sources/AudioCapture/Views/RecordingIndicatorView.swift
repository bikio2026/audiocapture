import SwiftUI

struct RecordingIndicatorView: View {
    let duration: String
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .opacity(isPulsing ? 1.0 : 0.3)
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isPulsing)

            Text(duration)
                .font(.system(.title2, design: .monospaced))

            Text("REC")
                .font(.caption)
                .foregroundColor(.red)
                .fontWeight(.bold)
        }
        .onAppear { isPulsing = true }
    }
}
