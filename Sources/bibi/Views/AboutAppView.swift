import SwiftUI

/**
 * 关于应用页面。
 *
 * 使用与工具页一致的原生列表风格：动态背景、insetGrouped 分组。
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
        ZStack {
            AnimatedBackground()

            List {
                Section {
                    appIdentity
                        .frame(maxWidth: .infinity)
                }
                .listRowBackground(Color.clear)

                Section("信息") {
                    aboutRow(title: "版本", value: versionText)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: handleVersionTap)
                    aboutRow(title: "构建", value: buildText)
                    aboutRow(title: "系统要求", value: "iOS 26 或更高版本")
                }

                Section("数据与隐私") {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("对话与应用日志", systemImage: "lock.shield")
                            .font(.bibiCaptionSemibold)
                        Text("对话和应用日志保存在当前设备。位置、联系人和日历仅在你触发对应工具并授权后读取，用于本次智能体回答；日志不会记录 API Key。")
                            .font(.bibiCaption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("关于应用")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(isPresented: $showsLogs) {
            AppLogView()
        }
    }

    /// 应用标识：品牌图标、名称与标语。
    private var appIdentity: some View {
        VStack(spacing: 12) {
            brandIcon

            Text("星枢")
                .font(.bibiLargeTitle)
            Text("让每件事，都办得妥帖")
                .font(.bibiCaption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    /**
     * 品牌图标。
     *
     * 优先从模块资源包加载品牌图标；加载失败时回退到应用图标，避免空白。
     *
     * @returns 品牌图标视图
     * @author xiangwei
     */
    private var brandIcon: some View {
        loadBrandIcon()
            .resizable()
            .scaledToFill()
            .frame(width: 84, height: 84)
            .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
            .shadow(color: Color.black.opacity(0.12), radius: 10, y: 5)
            .accessibilityHidden(true)
    }

    /**
     * 加载品牌图标。
     *
     * @returns 品牌图标图片，加载失败时回退到应用图标
     * @author xiangwei
     */
    private func loadBrandIcon() -> Image {
        if let url = Bundle.module.url(forResource: "icon", withExtension: "png"),
           let uiImage = UIImage(contentsOfFile: url.path) {
            return Image(uiImage: uiImage)
        }
        return Image("AppIcon")
    }

    /**
     * 构建关于信息行。
     *
     * @param title 信息名称
     * @param value 信息值
     * @returns 关于信息行
     * @author xiangwei
     */
    private func aboutRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .font(.bibiMonospacedCaption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    /**
     * 处理版本号连续点击并打开诊断日志。
     * @author xiangwei
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
