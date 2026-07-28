# iOS 26 Liquid Glass API 速查

> WWDC 2025 发布，iOS 26 起可用。系统在渲染层处理折射、高光、自适应阴影。

---

## 核心修饰符

```swift
// 给任意视图添加玻璃材质
.glassEffect()
.glassEffect(.regular)                          // 默认
.glassEffect(.clear, in: .capsule)              // 高透明 + 自定义形状
.glassEffect(.regular, in: .rect(cornerRadius: 20))
.glassEffect(.regular.interactive())            // iOS 交互模式
.glassEffect(.regular.tint(.blue))              // 着色
.glassEffect(.regular.interactive().tint(.orange))
.glassEffect(isEnabled: false)                   // 条件关闭
```

## Glass 变体

| 变体 | 用途 |
|------|------|
| `.regular` | 默认，标准玻璃，用于工具栏、标签栏、卡片 |
| `.clear` | 高透明，适合在媒体内容上叠加，需要配合 dimming |
| `.identity` | 无效果，用于条件切换 |

### 修饰符链

```swift
.regular              // 基础
.regular.tint(.blue)  // 着色
.regular.interactive()           // 交互反馈（缩放、闪烁、高光）
.regular.interactive().tint(.pink)
```

## 形状自定义

```swift
.glassEffect(in: .capsule)                      // 默认
.glassEffect(in: .circle)
.glassEffect(in: .rect(cornerRadius: 16))
.glassEffect(in: .rect(cornerRadius: .containerConcentric)) // 自动匹配父容器圆角
```

## GlassEffectContainer

多个玻璃元素必须共用一个容器，否则视觉不一致：

```swift
GlassEffectContainer(spacing: 12) {
    HStack {
        Button("A") { }.glassEffect()
        Button("B") { }.glassEffect()
        Button("C") { }.glassEffect()
    }
}
```

- 玻璃不能采样其他玻璃，容器提供共享采样区域
- `spacing` 控制元素间融合距离
- 同容器内的元素靠近到 `spacing` 阈值时自动融合

## Morphing 动画

```swift
struct MorphingDemo: View {
    @State private var isExpanded = false
    @Namespace private var ns

    var body: some View {
        GlassEffectContainer(spacing: 20) {
            HStack(spacing: 12) {
                if isExpanded {
                    Button("相机", systemImage: "camera") { }
                        .glassEffect(.regular.interactive())
                        .glassEffectID("camera", in: ns)
                }
                Button {
                    withAnimation(.bouncy) { isExpanded.toggle() }
                } label: {
                    Image(systemName: isExpanded ? "xmark" : "plus")
                }
                .buttonStyle(.glassProminent)
                .glassEffectID("toggle", in: ns)
            }
        }
    }
}
```

四个条件缺一不可：

1. 所有元素在同一个 `GlassEffectContainer` 内
2. 每个元素通过 `.glassEffectID("id", in: namespace)` 绑定唯一 ID
3. 共享一个 `@Namespace`
4. 状态变化包裹在 `withAnimation` 中

## 按钮样式

```swift
.buttonStyle(.glass)           // 标准玻璃按钮
.buttonStyle(.glassProminent)  // 强调玻璃按钮
.buttonBorderShape(.circle)    // 圆形边框
.controlSize(.extraLarge)      // 大号控制
```

## API 签名

```swift
func glassEffect<S: Shape>(
    _ glass: Glass = .regular,
    in shape: S = DefaultGlassEffectShape,
    isEnabled: Bool = true
) -> some View

func glassEffectID<ID: Hashable>(
    _ id: ID,
    in namespace: Namespace.ID
) -> some View

GlassEffectContainer(spacing: CGFloat = 0) { }

enum GlassEffectTransition {
    case identity
    case matchedGeometry   // 默认
    case materialize
}
```

### 类型说明

| 类型 | 说明 |
|------|------|
| `DefaultGlassEffectShape` | 系统默认的玻璃形状（`Capsule`），当不指定 `in:` 参数时使用。等效于 `.glassEffect(.regular, in: .capsule)` |
| `GlassEffectTransition` | 玻璃元素的过渡动画类型。`.matchedGeometry`（默认）在 morphing 时使用匹配几何动画；`.materialize` 适合从无到有的出现；`.identity` 禁用过渡 |
| `Glass` | 玻璃变体枚举，`.regular` / `.clear` / `.identity` 三种 |

## 注意事项

- **不要用 Liquid Glass 做内容层背景**，它是导航层材质。内容层用 `.thinMaterial` / `.regularMaterial`
- **`.clipped()` 会破坏玻璃效果**，如果玻璃元素在 ScrollView 内，提出来用 `.overlay`
- **`Form` 中 `.glassEffect()` 无效**，改用 `List`
- **暗色模式下 `.tint()` 饱和度翻倍**，测试注意
- **`.interactive()` 需要 Apple Intelligence 支持**（A17 Pro+ / iPhone 15 Pro 系列、iPhone 16/17 全系、M1+ iPad），不支持时自动降级为标准玻璃效果，不影响功能
- **快照测试不稳定**，玻璃高光依赖设备姿态

## 兼容性

| API | 最低版本 |
|-----|----------|
| `.glassEffect()` | iOS 26 |
| `GlassEffectContainer` | iOS 26 |
| `.glassEffectID()` | iOS 26 |
| `.buttonStyle(.glass)` | iOS 26 |
| `MeshGradient` | iOS 18 |
| `.ultraThinMaterial` | iOS 15（旧版回退） |

## 旧版回退方案

```swift
if #available(iOS 26, *) {
    content.glassEffect()
} else {
    content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.3), lineWidth: 1))
}
```

## bibi-ios 组件级 Glass 使用指引

**核心原则**：Liquid Glass 是导航层材质，不做内容层背景。内容层用 `.thinMaterial` / `.regularMaterial`。

### 使用对照表

| 组件 | 是否用 Glass | 材质选择 | 理由 |
|------|-------------|----------|------|
| TabBar / Toolbar | ✅ 用 | `.glassEffect()` | 导航层，Glass 的本职 |
| InputBar（输入工具栏） | ✅ 用 | `.glassEffect()` | 导航层输入控件 |
| ConnectionBanner（连接横幅） | ✅ 用 | `.glassEffect()` | 导航层状态条 |
| 空状态英雄区按钮 | ✅ 用 | `.buttonStyle(.glassProminent)` | 引导操作，强调视觉 |
| 设置页按钮 | ✅ 用 | `.buttonStyle(.glass)` | 交互控件 |
| 用户消息气泡 | ❌ 不用 | 暖金纯色背景 | 内容层 |
| 助手消息气泡 | ❌ 不用 | `.thinMaterial` | 内容层，需半透明但不需玻璃折射 |
| 工具调用卡片 | ❌ 不用 | `.regularMaterial` + 边框 | 内容层卡片 |
| 工具结果卡片 | ❌ 不用 | `.thinMaterial` | 内容层 |
| 对话列表行 | ❌ 不用 | `List` 默认样式 | `Form`/`List` 中 `.glassEffect()` 无效 |
| ThinkingIndicator | ❌ 不用 | `.thinMaterial` | 内容层临时组件 |

### 代码示例

```swift
// ✅ 正确：导航层用 Glass
InputBar()
    .glassEffect(.regular, in: .rect(cornerRadius: 16))

// ✅ 正确：内容层用 Material
MessageBubble(role: .assistant, text: "您本月共支出 ¥4,280.00")
    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))

// ❌ 错误：内容层用 Glass（违反原则）
MessageBubble(role: .assistant, text: "...")
    .glassEffect()  // 不要这样做
```

### 注意事项

- 玻璃元素在 `ScrollView` 内时，用 `.overlay` 提出 ScrollView 层级，避免 `.clipped()` 破坏效果
- 多个玻璃元素（如 InputBar 上的按钮）必须共用 `GlassEffectContainer`
- 暗色模式下 `.tint()` 饱和度翻倍，需单独测试

---

## 参考链接

- [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)
- [Build a SwiftUI app with the new design - WWDC25](https://developer.apple.com/videos/play/wwdc2025/323/)
- [Meet Liquid Glass - WWDC25](https://developer.apple.com/videos/play/wwdc2025/219/)
