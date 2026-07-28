import SwiftUI

/**
 * PC 配对码输入页
 *
 * 用户输入 PC 端显示的 6 位配对码，建立连接。
 *
 * @author xiangwei
 */
struct PairingView: View {
    let pc: PCDevice
    let connection: ConnectionManager
    let onConnected: () -> Void

    @State private var code = ""
    @State private var isLoading = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Text("连接 \(pc.name)")
                .font(.bibiTitle)
                .foregroundColor(.primary)

            Text("请在电脑端笔笔设置页获取配对码，然后输入下方输入框")
                .font(.bibiCaption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            // 6 位配对码输入
            TextField("输入 6 位配对码", text: $code)
                .font(.system(size: 32, design: .monospaced))
                .multilineTextAlignment(.center)
                .keyboardType(.numberPad)
                .padding()
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .disabled(isLoading)

            if let error = error {
                Text(error)
                    .font(.bibiCaption)
                    .foregroundColor(.errorRed)
            }

            Button(action: pair) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                } else {
                    Text("连接")
                        .font(.bibiButton)
                }
            }
            .buttonStyle(.glassProminent)
            .disabled(code.count != 6 || isLoading)

            Spacer()
        }
        .padding(24)
    }

    private func pair() {
        guard code.count == 6 else { return }
        isLoading = true
        error = nil

        Task { @MainActor in
            do {
                try await connection.connect(to: pc, pairingCode: code)
                await MainActor.run {
                    isLoading = false
                    onConnected()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    self.error = error.localizedDescription
                }
            }
        }
    }
}
