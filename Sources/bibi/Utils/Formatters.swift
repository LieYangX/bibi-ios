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
}
