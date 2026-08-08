import SwiftUI

/**
 * 手动输入 IP 连接页。
 *
 * 在 Bonjour 搜索不到设备时，允许手动输入电脑 IP 测试连通性并完成配对。
 *
 * @author xiangwei
 */
struct ManualConnectionView: View {
    let connection: ConnectionManager
    let onConnected: () -> Void

    @State private var ip = ""
    @State private var port = "19878"
    @State private var isTesting = false
    @State private var probe: ConnectionProbeResult?
    @State private var showPairing = false
    @State private var manualPC: PCDevice?
    @Environment(\.dismiss) private var dismiss

    /// 测试结果文本。
    private var resultText: String {
        if isTesting {
            return "正在连接 \(ip)…"
        }
        return probe?.message ?? "输入 IP 地址后点击测试连接"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Image(systemName: "network")
                    .font(.bibiLargeTitle)
                    .foregroundStyle(Color.brandGold)
                    .frame(width: 72, height: 72)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .padding(.top, 16)

                Text("手动连接电脑")
                    .font(.bibiTitle)
                    .padding(.top, 16)

                Text("搜索不到设备时，可手动输入电脑在局域网中的 IP 地址")
                    .font(.bibiCaption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
                    .padding(.horizontal, 32)

                VStack(spacing: 14) {
                    HStack(spacing: 10) {
                        TextField("IP 地址，如 192.168.1.100", text: $ip)
                            .keyboardType(.numbersAndPunctuation)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        TextField("端口", text: $port)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.center)
                            .frame(width: 84)
                    }
                    .font(.bibiBody)
                    .padding(.horizontal, 16)
                    .frame(height: 50)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(isReachable ? Color.successGreen.opacity(0.7) : Color.hairline, lineWidth: 1)
                    }
                    .disabled(isTesting)

                    Button(action: test) {
                        if isTesting {
                            ProgressView()
                                .tint(.primary)
                        } else {
                            Text(isReachable ? "重新测试" : "测试连接")
                                .font(.bibiButton)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.brandGold)
                    .controlSize(.extraLarge)
                    .disabled(!isValidInput || isTesting)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)

                Label(resultText, systemImage: resultIcon)
                    .font(.bibiCaption)
                    .foregroundStyle(resultColor)
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)
                    .padding(.horizontal, 24)

                if isReachable {
                    Button {
                        manualPC = connection.makeManualPC(ip: ip, port: Int(port) ?? 19878)
                        showPairing = true
                    } label: {
                        Label("输入配对码连接", systemImage: "link.badge.plus")
                            .font(.bibiBodyMedium)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .tint(.brandGold)
                    .controlSize(.extraLarge)
                    .padding(.horizontal, 24)
                    .padding(.top, 10)
                }

                Spacer(minLength: 12)
            }
            .background(AnimatedBackground())
            .navigationTitle("手动连接")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showPairing) {
                if let pc = manualPC {
                    PairingView(pc: pc, connection: connection, onConnected: {
                        onConnected()
                        dismiss()
                    })
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
                }
            }
        }
    }

    /// 是否可达（收到服务端响应即可进入配对）。
    private var isReachable: Bool {
        probe?.reachable == true
    }

    /// 输入是否合法。
    private var isValidInput: Bool {
        !ip.trimmingCharacters(in: .whitespaces).isEmpty && (Int(port) ?? 0) > 0
    }

    /// 结果图标。
    private var resultIcon: String {
        if isTesting {
            return "antenna.radiowaves.left.and.right"
        }
        return isReachable ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
    }

    /// 结果颜色。
    private var resultColor: Color {
        if isTesting {
            return .secondary
        }
        return isReachable ? Color.successGreen : Color.errorRed
    }

    /**
     * 测试指定 IP 的连通性，失败时展示具体错误原因。
     * @author xiangwei
     */
    private func test() {
        isTesting = true
        probe = nil
        Task { @MainActor in
            probe = await connection.testConnection(
                ip: ip.trimmingCharacters(in: .whitespaces),
                port: Int(port) ?? 19878
            )
            isTesting = false
        }
    }
}
