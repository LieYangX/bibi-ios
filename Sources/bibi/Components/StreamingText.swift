import SwiftUI

/**
 * 流式文本渲染组件
 *
 * 随着文本追加自动滚动到最新内容。
 *
 * @author xiangwei
 */
struct StreamingText: View {
    let text: String
    @State private var scrollID = UUID()

    var body: some View {
        ScrollViewReader { proxy in
            Text(text)
                .font(.bibiBody)
                .lineSpacing(4)
                .id(scrollID)
                .onChange(of: text) { _, _ in
                    scrollID = UUID()
                    withAnimation {
                        proxy.scrollTo(scrollID, anchor: .bottom)
                    }
                }
        }
    }
}
