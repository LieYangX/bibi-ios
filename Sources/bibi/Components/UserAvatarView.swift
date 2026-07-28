import SwiftUI

/**
 * 本地用户头像
 *
 * 暖金色圆形背景 + 用户名称首字母。
 *
 * @author xiangwei
 */
struct UserAvatarView: View {
    let name: String
    let color: Color
    let size: CGFloat

    var body: some View {
        Text(String(name.prefix(1)))
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: size, height: size)
            .background(color)
            .clipShape(Circle())
    }
}
