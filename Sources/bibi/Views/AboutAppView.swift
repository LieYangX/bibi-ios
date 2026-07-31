import SwiftUI

/**
 * 关于应用页面。
 *
 * @author xiangwei
 */
struct AboutAppView: View {
    /// 连续点击判定间隔。
    private static let tapInterval: TimeInterval = 1.5

    @State private var versionTapCount = 0
    @State private var lastVersionTapAt: Date?
    @State private var showsLogs = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                appIdentity
                informationGroup
                privacyNotice
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .padding(.bottom, 36)
        }
        .background(Color.contentBackground.ignoresSafeArea())
        .navigationTitle("关于应用")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showsLogs) {
            AppLogView()
        }
    }

    private var appIdentity: some View {
        VStack(spacing: 12) {
            Image(systemName: "pencil.and.list.clipboard")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(Color.brandGoldDark)
                .frame(width: 84, height: 84)
                .background(Color.brandGoldLight, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text("笔笔")
                .font(.bibiLargeTitle)
            Text("让每一笔都有迹可循")
                .font(.bibiCaption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var informationGroup: some View {
        VStack(spacing: 0) {
            aboutRow(title: "版本", value: versionText)
                .contentShape(Rectangle())
                .onTapGesture(perform: handleVersionTap)
            Divider()
            aboutRow(title: "构建", value: buildText)
            Divider()
            aboutRow(title: "系统要求", value: "iOS 26 或更高版本")
        }
        .padding(.horizontal, 14)
        .background(Color.contentCardBackground, in: BibiShape.contentCard)
    }

    private var privacyNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("数据与隐私", systemImage: "lock.shield")
                .font(.bibiCaptionSemibold)
            Text("对话和应用日志保存在当前设备。位置、联系人和日历仅在你触发对应工具并授权后读取，用于本次智能体回答；日志不会记录 API Key。")
                .font(.bibiCaption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.contentCardBackground, in: BibiShape.contentCard)
    }

    /**
     * 构建关于信息行。
     *
     * @param title 信息名称
     * @param value 信息值
     * @returns 关于信息行
     */
    private func aboutRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .font(.bibiMonospacedCaption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 14)
    }

    /**
     * 处理版本号连续点击并打开诊断日志。
     */
    private func handleVersionTap() {
        let now = Date()
        if let lastVersionTapAt,
           now.timeIntervalSince(lastVersionTapAt) > Self.tapInterval {
            versionTapCount = 0
        }

        lastVersionTapAt = now
        versionTapCount += 1

        guard versionTapCount >= 5 else { return }
        versionTapCount = 0
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        showsLogs = true
        Task {
            await AppLogger.shared.log(.info, category: "diagnostics", message: "用户打开应用日志页面")
        }
    }

    private var versionText: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    private var buildText: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }
}
