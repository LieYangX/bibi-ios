import SwiftUI

/// iOS 26 信息 App 风格交互演示
///
/// 在静态列表基础上增加可交互功能：
/// - 搜索框实时过滤消息
/// - 点击进入会话详情页
/// - 编辑模式多选删除
/// - 新建消息弹窗
/// - 麦克风录音动画反馈
struct ContentView: View {
    // 导航路径，用于手动控制页面跳转
    @State private var navigationPath = NavigationPath()

    // 搜索框文本
    @State private var searchText = ""

    // 是否处于编辑模式
    @State private var isEditing = false

    // 是否显示新建消息弹窗
    @State private var showComposeSheet = false

    // 是否显示录音界面
    @State private var showRecording = false

    // 当前选中的消息 ID
    @State private var selectedIDs = Set<UUID>()

    // 消息数据（可变，用于删除操作）
    @State private var messages: [MessageItem] = [
        .init(
            sender: "10010",
            content: "【啊是大飒飒撒打算撒打算",
            date: "昨天",
            avatarType: .defaultPerson
        ),
        .init(
            sender: "95555",
            content: "啊实打实的撒大苏打萨达a's'd",
            date: "2026/7/17",
            avatarType: .defaultPerson
        ),
        .init(
            sender: "10690760295102",
            content: "钉钉登录#ITQKB",
            date: "2026/7/8",
            avatarType: .defaultPerson
        ),
        .init(
            sender: "10690700367",
            content: "微信安全验证77",
            date: "2026/7/8",
            avatarType: .defaultPerson
        ),
        .init(
            sender: "萨达",
            content: "ᕙ(⇀‸↼‶)ᕗ ᕙ(⇀‸↼‶)ᕗ ᕙ(⇀‸↼‶)ᕗ",
            date: "2026/4/27",
            avatarType: .photo
        ),
        .init(
            sender: "阿斯顿",
            content: "🌍",
            date: "2026/3/17",
            avatarType: .photo
        ),
        .init(
            sender: "95516",
            content: "大苏打萨达sa'd",
            date: "2026/3/13",
            avatarType: .defaultPerson
        ),
        .init(
            sender: "12306",
            content: "【12306】候补订单已兑现成功，...",
            date: "2026/2/20",
            avatarType: .defaultPerson
        )
    ]

    // 根据搜索文本过滤后的消息
    private var filteredMessages: [MessageItem] {
        if searchText.isEmpty {
            return messages
        }
        return messages.filter {
            $0.sender.localizedCaseInsensitiveContains(searchText) ||
            $0.content.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                // 纯黑背景
                Color.black
                    .ignoresSafeArea()

                // 消息列表
                List(filteredMessages) { message in
                    MessageRow(
                        item: message,
                        isEditing: isEditing,
                        isSelected: selectedIDs.contains(message.id)
                    )
                    .listRowBackground(Color.black)
                    .listRowSeparator(.visible)
                    .listRowSeparatorTint(Color.white.opacity(0.12))
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        handleTap(message: message)
                    }
                    // 左滑删除
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            deleteMessage(message)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)

                // 录音动画覆盖层
                if showRecording {
                    RecordingOverlay()
                        .transition(.opacity.combined(with: .scale))
                }

                // 底部玻璃搜索栏
                VStack {
                    Spacer()

                    bottomSearchBar
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                }
            }
            .navigationTitle("信息")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(isEditing ? "完成" : "编辑") {
                        withAnimation(.snappy) {
                            isEditing.toggle()
                            selectedIDs.removeAll()
                        }
                    }
                    .font(.system(size: 17))
                    .foregroundStyle(.white)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if isEditing && !selectedIDs.isEmpty {
                        Button("删除") {
                            deleteSelectedMessages()
                        }
                        .font(.system(size: 17))
                        .foregroundStyle(.red)
                    } else {
                        Button(action: {}) {
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
            .sheet(isPresented: $showComposeSheet) {
                ComposeMessageSheet()
            }
            // 点击行进入详情页
            .navigationDestination(for: MessageItem.self) { message in
                MessageDetailView(message: message)
            }
        }
    }

    /// 处理消息行点击事件
    private func handleTap(message: MessageItem) {
        if isEditing {
            // 编辑模式：切换选中状态
            withAnimation(.snappy) {
                if selectedIDs.contains(message.id) {
                    selectedIDs.remove(message.id)
                } else {
                    selectedIDs.insert(message.id)
                }
            }
        } else {
            // 普通模式：跳转到详情页
            navigationPath.append(message)
        }
    }

    /// 删除单条消息
    private func deleteMessage(_ message: MessageItem) {
        withAnimation {
            messages.removeAll { $0.id == message.id }
            selectedIDs.remove(message.id)
        }
    }

    /// 删除所有选中的消息
    private func deleteSelectedMessages() {
        withAnimation {
            messages.removeAll { selectedIDs.contains($0.id) }
            selectedIDs.removeAll()
            isEditing = false
        }
    }

    /// 底部玻璃质感搜索栏
    private var bottomSearchBar: some View {
        HStack(spacing: 12) {
            // 搜索输入框
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))

                TextField("搜索", text: $searchText)
                    .font(.system(size: 17))
                    .foregroundStyle(.white)
                    .tint(.white)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .frame(maxWidth: .infinity)
            .glassEffect(.regular, in: .capsule)

            // 麦克风按钮：显示录音动画
            Button {
                withAnimation(.bouncy) {
                    showRecording = true
                }
                // 2 秒后自动关闭录音界面
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation {
                        showRecording = false
                    }
                }
            } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: .circle)
            }

            // 新建消息按钮
            Button {
                showComposeSheet = true
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
        }
    }
}

/// 单条消息数据模型
struct MessageItem: Identifiable, Hashable {
    let id = UUID()
    let sender: String
    let content: String
    let date: String
    let avatarType: AvatarType

    enum AvatarType {
        case defaultPerson
        case photo
    }
}

/// 消息列表行视图
struct MessageRow: View {
    let item: MessageItem
    let isEditing: Bool
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            // 编辑模式下的选择圆圈
            if isEditing {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? .blue : .white.opacity(0.4))
                    .animation(.snappy, value: isSelected)
            }

            // 头像
            avatarView
                .frame(width: 48, height: 48)

            // 中间内容
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.sender)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)

                    Spacer()

                    Text(item.date)
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.5))
                }

                Text(item.content)
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            // 非编辑模式下显示右侧箭头
            if !isEditing {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .padding(.vertical, 4)
    }

    /// 头像视图：默认联系人图标或真实照片占位
    @ViewBuilder
    private var avatarView: some View {
        switch item.avatarType {
        case .defaultPerson:
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.35))

                Image(systemName: "person.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.white.opacity(0.6))
            }

        case .photo:
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    Text(String(item.sender.prefix(1)))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                )
        }
    }
}

/// 消息详情页
struct MessageDetailView: View {
    let message: MessageItem
    @State private var replyText = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // 模拟历史消息气泡
                ScrollView {
                    VStack(spacing: 12) {
                        MessageBubble(text: message.content, isIncoming: true)
                        MessageBubble(text: "已收到，谢谢！", isIncoming: false)
                    }
                    .padding()
                }

                // 底部输入框
                HStack(spacing: 12) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.title3)
                            .foregroundStyle(.white)
                    }

                    TextField("信息", text: $replyText)
                        .padding(.horizontal, 12)
                        .frame(height: 40)
                        .glassEffect(.regular, in: .capsule)

                    Button {
                        replyText = ""
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.blue)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
        }
        .navigationTitle(message.sender)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 消息气泡视图
struct MessageBubble: View {
    let text: String
    let isIncoming: Bool

    var body: some View {
        HStack {
            if isIncoming {
                Text(text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.gray.opacity(0.3))
                    )
                    .foregroundStyle(.white)
                Spacer()
            } else {
                Spacer()
                Text(text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.blue)
                    )
                    .foregroundStyle(.white)
            }
        }
    }
}

/// 新建消息弹窗
struct ComposeMessageSheet: View {
    @State private var recipient = ""
    @State private var messageBody = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 20) {
                    HStack {
                        Text("收件人:")
                            .foregroundStyle(.white.opacity(0.7))
                        TextField("输入号码或姓名", text: $recipient)
                            .foregroundStyle(.white)
                            .tint(.white)
                    }
                    .padding()
                    .glassEffect(.regular, in: .rect(cornerRadius: 12))
                    .padding(.horizontal)

                    TextEditor(text: $messageBody)
                        .padding(8)
                        .foregroundStyle(.white)
                        .tint(.white)
                        .glassEffect(.clear, in: .rect(cornerRadius: 16))
                        .padding(.horizontal)

                    Spacer()
                }
                .padding(.top, 20)
            }
            .navigationTitle("新信息")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("发送") { dismiss() }
                        .foregroundStyle(.blue)
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

/// 录音动画覆盖层
struct RecordingOverlay: View {
    @State private var scale = 1.0

    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.red)
                    .scaleEffect(scale)
                    .animation(
                        Animation.easeInOut(duration: 0.8)
                            .repeatForever(autoreverses: true),
                        value: scale
                    )
                    .onAppear {
                        scale = 1.2
                    }

                Text("正在录音...")
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            .padding(40)
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
        }
    }
}
