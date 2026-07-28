import SwiftUI

/**
 * 用户选择器列表
 *
 * 显示本地用户列表，支持选择和新用户创建。
 *
 * @author xiangwei
 */
struct UserPickerSection: View {
    let users: [LocalUser]
    let currentUser: LocalUser?
    let onSelect: (LocalUser) -> Void
    let onCreate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("本地用户")
                .font(.bibiCaptionSemibold)
                .foregroundColor(.secondary)

            ForEach(users) { user in
                Button(action: { onSelect(user) }) {
                    HStack(spacing: 12) {
                        UserAvatarView(
                            name: user.displayName,
                            color: Color(hex: user.avatarColor),
                            size: 32
                        )

                        Text(user.displayName)
                            .font(.bibiBody)
                            .foregroundColor(.primary)

                        Spacer()

                        if user.id == currentUser?.id {
                            Image(systemName: "checkmark")
                                .font(.caption)
                                .foregroundColor(.brandGold)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }

            Button(action: onCreate) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.brandGold)
                    Text("新增用户")
                        .font(.bibiBody)
                        .foregroundColor(.brandGold)
                }
            }
            .buttonStyle(.plain)
        }
    }
}
