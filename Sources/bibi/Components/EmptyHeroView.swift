import SwiftUI

/**
 * 空对话引导区。
 *
 * 仅展示品牌标识和当前用户问候语。
 *
 * @author xiangwei
 */
struct EmptyHeroView: View {
    let userName: String

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 32)

            brandMark

            Text("你好，\(userName)")
                .font(.bibiTitle)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            Spacer(minLength: 32)
        }
        .padding(.horizontal, 24)
    }

    private var brandMark: some View {
        Image("AppIcon")
            .resizable()
            .scaledToFill()
            .frame(width: 84, height: 84)
            .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 10, y: 5)
            .accessibilityHidden(true)
    }
}
