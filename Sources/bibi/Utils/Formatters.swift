import Foundation

// MARK: - 格式化工具

enum AppFormatters {

    /// 货币格式化器（人民币）
    static let currency: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "CNY"
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        return formatter
    }()

    /// 短日期格式化器（如 "7月26日"）
    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter
    }()

    /// 完整日期格式化器（如 "2026年7月26日"）
    static let fullDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter
    }()

    /// 短时间格式化器（如 "14:32"）
    static let shortTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    /// 格式化金额为人民币字符串
    /// - Parameter amount: 金额
    /// - Returns: 格式化后的字符串，如 "¥1,234"
    static func formatAmount(_ amount: Double) -> String {
        currency.string(from: NSNumber(value: amount)) ?? "¥\(amount)"
    }

    /// 根据日期返回分组标签
    /// - Parameter date: 日期
    /// - Returns: 分组标签（"今天"、"昨天"、"本周"、"本月"、具体日期）
    static func dateGroupLabel(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "今天" }
        if calendar.isDateInYesterday(date) { return "昨天" }
        if calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) { return "本周" }
        if calendar.isDate(date, equalTo: Date(), toGranularity: .month) { return "本月" }
        return shortDate.string(from: date)
    }

    /// 格式化日期为短格式
    static func formatShortDate(_ date: Date) -> String {
        shortDate.string(from: date)
    }

    /// 格式化为对话列表使用的消息时间。
    ///
    /// 今天返回 "HH:mm"，昨天返回 "昨天 HH:mm"，今年返回 "M月d日 HH:mm"，更早返回 "yyyy/M/d HH:mm"。
    /// - Parameter date: 对话最后更新时间
    /// - Returns: 适合列表展示的时间字符串
    static func conversationTime(_ date: Date) -> String {
        let calendar = Calendar.current
        let time = shortTime.string(from: date)
        if calendar.isDateInToday(date) {
            return time
        }
        if calendar.isDateInYesterday(date) {
            return "昨天 \(time)"
        }
        if calendar.isDate(date, equalTo: Date(), toGranularity: .year) {
            return "\(shortDate.string(from: date)) \(time)"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy/M/d"
        return "\(formatter.string(from: date)) \(time)"
    }

    /// 格式化为气泡消息时间。
    ///
    /// 今天返回 "HH:mm"，非今天返回 "yyyy年M月d日"。
    /// - Parameter date: 消息时间戳
    /// - Returns: 适合气泡消息展示的时间字符串
    static func messageTime(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return shortTime.string(from: date)
        }
        return fullDate.string(from: date)
    }
}
