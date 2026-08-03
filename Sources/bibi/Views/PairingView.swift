import SwiftUI

/**
 * PC 配对码输入页。
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
    @FocusState private var isCodeFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Image(systemName: "desktopcomputer.and.iphone")
                    .font(.bibiLargeTitle)
                    .foregroundStyle(Color.brandGold)
                    .frame(width: 72, height: 72)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .padding(.top, 12)

                Text(pc.name)
                    .font(.bibiTitle)
                    .padding(.top, 18)

                Text("输入电脑端显示的 6 位配对码")
                    .font(.bibiCaption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)

                TextField("000000", text: $code)
                    .font(.system(size: 34, weight: .semibold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($isCodeFocused)
                    .padding(.horizontal, 18)
                    .frame(height: 64)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(isCodeValid ? Color.brandGold.opacity(0.7) : Color.hairline, lineWidth: 1)
                    }
                    .disabled(isLoading)
                    .padding(.top, 24)
                    .onChange(of: code) { _, newValue in
                        code = String(newValue.filter(\.isNumber).prefix(6))
                    }

                if let error {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(.bibiCaption)
                        .foregroundStyle(Color.errorRed)
                        .multilineTextAlignment(.center)
                        .padding(.top, 12)
                }

                Button(action: pair) {
                    if isLoading {
                        ProgressView()
                            .tint(.primary)
                    } else {
                        Text("连接")
                            .font(.bibiButton)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.glassProminent)
                .tint(.brandGold)
                .controlSize(.extraLarge)
                .disabled(!isCodeValid || isLoading)
                .padding(.top, 22)

                Spacer(minLength: 12)
            }
            .padding(.horizontal, 24)
            .navigationTitle("连接电脑")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                    .disabled(isLoading)
                }
            }
            .onAppear {
                isCodeFocused = true
            }
            .interactiveDismissDisabled(isLoading)
        }
    }

    private var isCodeValid: Bool {
        code.count == 6
    }

    private func pair() {
        guard isCodeValid else { return }
        isLoading = true
        error = nil

        Task { @MainActor in
            do {
                try await connection.connect(to: pc, pairingCode: code)
                await AppLogger.shared.log(
                    .info,
                    category: "connection",
                    message: "电脑配对成功",
                    metadata: ["device_name": pc.name]
                )
                isLoading = false
                onConnected()
                dismiss()
            } catch {
                isLoading = false
                self.error = error.localizedDescription
                await AppLogger.shared.log(
                    .error,
                    category: "connection",
                    message: "电脑配对失败: \(error.localizedDescription)",
                    metadata: ["device_name": pc.name]
                )
            }
        }
    }
}
