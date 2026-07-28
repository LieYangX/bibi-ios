import SwiftUI

/**
 * 工具描述行
 *
 * 显示 PC 端工具的名称和描述。
 *
 * @author xiangwei
 */
struct ToolRow: View {
    let tool: PcToolDef

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 16))
                .foregroundColor(.brandGold)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(tool.name)
                    .font(.bibiBody)
                    .foregroundColor(.primary)

                Text(tool.description)
                    .font(.bibiCaption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}
