import Contacts
@preconcurrency import CoreLocation
import EventKit
import Foundation
import HealthKit
import UIKit

/**
 * 本机工具服务。
 *
 * 管理无需连接电脑即可执行的 iOS 本机能力，并在需要时触发系统权限授权。
 *
 * @author xiangwei
 */
@MainActor
final class LocalToolService {
    /// 查询当前系统时间的工具名。
    static let currentTimeToolName = "get_current_time"

    /// 查询设备信息的工具名。
    static let deviceInfoToolName = "get_device_info"

    /// 查询电池状态的工具名。
    static let batteryStatusToolName = "get_battery_status"

    /// 查询应用信息的工具名。
    static let appInfoToolName = "get_app_info"

    /// 查询当前位置的工具名。
    static let currentLocationToolName = "get_current_location"

    /// 搜索联系人的工具名。
    static let searchContactsToolName = "search_contacts"

    /// 查询日历日程的工具名。
    static let calendarEventsToolName = "get_calendar_events"

    /// 查询健康信息的工具名。
    static let healthInfoToolName = "get_health_info"

    /// 默认联系人返回数量。
    private static let defaultContactLimit = 10

    /// 最大联系人返回数量。
    private static let maximumContactLimit = 30

    /// 默认日程查询天数。
    private static let defaultCalendarDays = 7

    /// 最大日程查询天数。
    private static let maximumCalendarDays = 30

    /// 默认日程返回数量。
    private static let defaultCalendarEventLimit = 20

    /// 最大日程返回数量。
    private static let maximumCalendarEventLimit = 50

    /// 联系人数据存储。
    private let contactStore = CNContactStore()

    /// 日历数据存储。
    private let eventStore = EKEventStore()

    /// 健康数据存储。
    private let healthStore = HKHealthStore()

    /// 需要请求授权的健康数据类型。
    private var healthDataTypes: Set<HKSampleType> {
        let identifiers: [HKQuantityTypeIdentifier] = [
            .stepCount, .heartRate, .restingHeartRate, .activeEnergyBurned, .distanceWalkingRunning
        ]
        let quantityTypes = identifiers.compactMap { HKQuantityType.quantityType(forIdentifier: $0) }
        let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)
        return Set(quantityTypes + [sleepType].compactMap { $0 })
    }

    /// 当前正在等待的定位请求。
    private var locationRequest: LocationRequest?

    /// 本机可用工具。
    let availableTools: [PcToolDef] = [
        PcToolDef(
            name: LocalToolService.currentTimeToolName,
            description: "获取当前设备的系统日期、时间、时区和 UTC 偏移。用户询问现在几点或当前日期时使用。",
            parameters: LocalToolService.emptyParameters()
        ),
        PcToolDef(
            name: LocalToolService.deviceInfoToolName,
            description: "获取当前设备名称、设备类型、系统版本、区域和时区，无需系统授权。",
            parameters: LocalToolService.emptyParameters()
        ),
        PcToolDef(
            name: LocalToolService.batteryStatusToolName,
            description: "获取当前设备电量、充电状态和低电量模式，无需系统授权。",
            parameters: LocalToolService.emptyParameters()
        ),
        PcToolDef(
            name: LocalToolService.appInfoToolName,
            description: "获取笔笔应用名称、版本、构建号和 Bundle ID，无需系统授权。",
            parameters: LocalToolService.emptyParameters()
        ),
        PcToolDef(
            name: LocalToolService.currentLocationToolName,
            description: "获取当前设备的经纬度、海拔和定位精度。仅在用户明确询问位置时使用，需要定位权限。",
            parameters: LocalToolService.emptyParameters()
        ),
        PcToolDef(
            name: LocalToolService.searchContactsToolName,
            description: "按姓名搜索系统联系人并返回电话和邮箱。仅在用户明确要求查找联系人时使用，需要通讯录权限。",
            parameters: PcToolParameters(
                schema: [
                    "type": AnyCodable("object"),
                    "properties": AnyCodable([
                        "query": [
                            "type": "string",
                            "description": "联系人姓名或姓名片段"
                        ],
                        "limit": [
                            "type": "integer",
                            "description": "最多返回数量，范围 1 到 30",
                            "minimum": 1,
                            "maximum": 30
                        ]
                    ] as [String: Any]),
                    "required": AnyCodable(["query"]),
                    "additionalProperties": AnyCodable(false)
                ]
            )
        ),
        PcToolDef(
            name: LocalToolService.calendarEventsToolName,
            description: "查询未来一段时间内的系统日历日程。仅在用户明确询问日程时使用，需要完整日历访问权限。",
            parameters: PcToolParameters(
                schema: [
                    "type": AnyCodable("object"),
                    "properties": AnyCodable([
                        "days": [
                            "type": "integer",
                            "description": "从今天开始查询的天数，范围 1 到 30",
                            "minimum": 1,
                            "maximum": 30
                        ],
                        "limit": [
                            "type": "integer",
                            "description": "最多返回数量，范围 1 到 50",
                            "minimum": 1,
                            "maximum": 50
                        ]
                    ] as [String: Any]),
                    "additionalProperties": AnyCodable(false)
                ]
            )
        ),
        PcToolDef(
            name: LocalToolService.healthInfoToolName,
            description: "获取今日健康与运动数据，包括步数、心率、睡眠时长、活动能量和步行距离。用户询问健康、运动、睡眠或身体数据时使用，需要健康访问权限。",
            parameters: LocalToolService.emptyParameters()
        )
    ]

    /**
     * 判断工具是否由本机执行。
     *
     * @param toolName 工具名
     * @returns 是否为本机工具
     * @author xiangwei
     */
    func canExecute(toolName: String) -> Bool {
        availableTools.contains { $0.name == toolName }
    }

    /**
     * 执行本机工具。
     *
     * @param toolName 工具名
     * @param args 工具参数
     * @returns 工具执行结果
     * @throws 工具参数、系统权限或执行异常
     * @author xiangwei
     */
    func execute(toolName: String, args: [String: Any]) async throws -> PcToolResult {
        let data: [String: Any]

        switch toolName {
        case Self.currentTimeToolName:
            data = currentTime()
        case Self.deviceInfoToolName:
            data = deviceInfo()
        case Self.batteryStatusToolName:
            data = batteryStatus()
        case Self.appInfoToolName:
            data = appInfo()
        case Self.currentLocationToolName:
            data = try await currentLocation()
        case Self.searchContactsToolName:
            data = try await searchContacts(args: args)
        case Self.calendarEventsToolName:
            data = try await calendarEvents(args: args)
        case Self.healthInfoToolName:
            data = try await healthInfo()
        default:
            throw LocalToolError.unsupportedTool(toolName)
        }

        return PcToolResult(success: true, data: AnyCodable(data), error: nil)
    }

    /**
     * 获取工具的中文显示名称。
     *
     * @param toolName 工具名
     * @returns 中文显示名称，不是本机工具时返回原始名称
     * @author xiangwei
     */
    static func displayName(for toolName: String) -> String {
        switch toolName {
        case currentTimeToolName:
            return "查询系统时间"
        case deviceInfoToolName:
            return "查询设备信息"
        case batteryStatusToolName:
            return "查询电池状态"
        case appInfoToolName:
            return "查询应用信息"
        case currentLocationToolName:
            return "查询当前位置"
        case searchContactsToolName:
            return "搜索系统联系人"
        case calendarEventsToolName:
            return "查询日历日程"
        case healthInfoToolName:
            return "查询健康数据"
        default:
            return toolName
        }
    }

    /**
     * 获取本机工具的系统图标名称。
     *
     * @param toolName 工具名
     * @returns SF Symbols 图标名，不是本机工具时返回空
     * @author xiangwei
     */
    static func iconName(for toolName: String) -> String? {
        switch toolName {
        case currentTimeToolName:
            return "clock.fill"
        case deviceInfoToolName:
            return "iphone"
        case batteryStatusToolName:
            return "battery.75percent"
        case appInfoToolName:
            return "info.circle.fill"
        case currentLocationToolName:
            return "location.fill"
        case searchContactsToolName:
            return "person.crop.circle"
        case calendarEventsToolName:
            return "calendar"
        case healthInfoToolName:
            return "heart.fill"
        default:
            return nil
        }
    }

    /**
     * 判断本机工具是否需要系统权限。
     *
     * @param toolName 工具名
     * @returns 是否需要系统授权
     * @author xiangwei
     */
    static func requiresPermission(_ toolName: String) -> Bool {
        switch toolName {
        case currentLocationToolName, searchContactsToolName, calendarEventsToolName, healthInfoToolName:
            return true
        default:
            return false
        }
    }

    /**
     * 获取本机工具成功提示。
     *
     * @param toolName 工具名
     * @returns 工具成功提示，不是本机工具时返回空
     * @author xiangwei
     */
    static func successSummary(for toolName: String) -> String? {
        switch toolName {
        case currentTimeToolName:
            return "已获取当前系统时间"
        case deviceInfoToolName:
            return "已获取设备信息"
        case batteryStatusToolName:
            return "已获取电池状态"
        case appInfoToolName:
            return "已获取应用信息"
        case currentLocationToolName:
            return "已获取当前位置"
        case searchContactsToolName:
            return "已完成联系人搜索"
        case calendarEventsToolName:
            return "已获取日历日程"
        case healthInfoToolName:
            return "已获取健康数据"
        default:
            return nil
        }
    }

    /**
     * 构建无参数工具的参数定义。
     *
     * @returns 空对象参数定义
     * @author xiangwei
     */
    private static func emptyParameters() -> PcToolParameters {
        PcToolParameters(
            schema: [
                "type": AnyCodable("object"),
                "properties": AnyCodable([String: Any]()),
                "additionalProperties": AnyCodable(false)
            ]
        )
    }

    /**
     * 获取当前系统时间。
     *
     * @returns 时间信息
     * @author xiangwei
     */
    private func currentTime() -> [String: Any] {
        let now = Date()
        let timeZone = TimeZone.current
        let localFormatter = DateFormatter()
        localFormatter.locale = Locale(identifier: "zh_CN")
        localFormatter.timeZone = timeZone
        localFormatter.dateFormat = "yyyy年M月d日 EEEE HH:mm:ss"

        return [
            "local_time": localFormatter.string(from: now),
            "iso8601": iso8601String(from: now),
            "time_zone": timeZone.identifier,
            "utc_offset_seconds": timeZone.secondsFromGMT(for: now),
            "unix_timestamp": Int(now.timeIntervalSince1970)
        ]
    }

    /**
     * 获取设备信息。
     *
     * @returns 设备与系统信息
     * @author xiangwei
     */
    private func deviceInfo() -> [String: Any] {
        let device = UIDevice.current
        return [
            "device_name": device.name,
            "device_model": device.model,
            "system_name": device.systemName,
            "system_version": device.systemVersion,
            "locale": Locale.current.identifier,
            "time_zone": TimeZone.current.identifier
        ]
    }

    /**
     * 获取电池状态。
     *
     * @returns 电量与节能状态
     * @author xiangwei
     */
    private func batteryStatus() -> [String: Any] {
        let device = UIDevice.current
        let wasMonitoringEnabled = device.isBatteryMonitoringEnabled
        device.isBatteryMonitoringEnabled = true
        defer {
            device.isBatteryMonitoringEnabled = wasMonitoringEnabled
        }

        let level = device.batteryLevel
        return [
            "battery_level_percent": level >= 0 ? Int((level * 100).rounded()) : -1,
            "battery_state": batteryStateName(device.batteryState),
            "low_power_mode_enabled": ProcessInfo.processInfo.isLowPowerModeEnabled
        ]
    }

    /**
     * 获取应用信息。
     *
     * @returns 应用版本与标识信息
     * @author xiangwei
     */
    private func appInfo() -> [String: Any] {
        let bundle = Bundle.main
        let appName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "笔笔"

        return [
            "app_name": appName,
            "version": bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知",
            "build_number": bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "未知",
            "bundle_identifier": bundle.bundleIdentifier ?? "未知"
        ]
    }

    /**
     * 获取当前位置。
     *
     * @returns 当前定位信息
     * @throws 定位权限或定位执行异常
     * @author xiangwei
     */
    private func currentLocation() async throws -> [String: Any] {
        let request = LocationRequest()
        locationRequest = request
        defer {
            locationRequest = nil
        }

        let location = try await request.start()
        return [
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "altitude_meters": location.altitude,
            "horizontal_accuracy_meters": location.horizontalAccuracy,
            "vertical_accuracy_meters": location.verticalAccuracy,
            "timestamp": iso8601String(from: location.timestamp),
            "accuracy_authorization": request.accuracyAuthorizationName
        ]
    }

    /**
     * 搜索系统联系人。
     *
     * @param args 工具参数
     * @returns 联系人搜索结果
     * @throws 参数、通讯录权限或读取异常
     * @author xiangwei
     */
    private func searchContacts(args: [String: Any]) async throws -> [String: Any] {
        let query = try requiredStringArgument("query", from: args)
        let limit = boundedIntegerArgument(
            "limit",
            from: args,
            defaultValue: Self.defaultContactLimit,
            maximumValue: Self.maximumContactLimit
        )
        try await ensureContactsAccess()

        let keys: [CNKeyDescriptor] = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor
        ]
        let predicate = CNContact.predicateForContacts(matchingName: query)
        let contacts = try contactStore.unifiedContacts(matching: predicate, keysToFetch: keys)
        let items = contacts.prefix(limit).map { contact in
            [
                "name": CNContactFormatter.string(from: contact, style: .fullName) ?? "未命名联系人",
                "organization": contact.organizationName,
                "phone_numbers": contact.phoneNumbers.map { $0.value.stringValue },
                "email_addresses": contact.emailAddresses.map { String($0.value) }
            ] as [String: Any]
        }

        return [
            "query": query,
            "count": items.count,
            "contacts": items
        ]
    }

    /**
     * 查询未来日历日程。
     *
     * @param args 工具参数
     * @returns 日程查询结果
     * @throws 日历权限或读取异常
     * @author xiangwei
     */
    private func calendarEvents(args: [String: Any]) async throws -> [String: Any] {
        let days = boundedIntegerArgument(
            "days",
            from: args,
            defaultValue: Self.defaultCalendarDays,
            maximumValue: Self.maximumCalendarDays
        )
        let limit = boundedIntegerArgument(
            "limit",
            from: args,
            defaultValue: Self.defaultCalendarEventLimit,
            maximumValue: Self.maximumCalendarEventLimit
        )
        try await ensureCalendarAccess()

        let startDate = Date()
        guard let endDate = Calendar.current.date(byAdding: .day, value: days, to: startDate) else {
            throw LocalToolError.calendarRangeUnavailable
        }

        let predicate = eventStore.predicateForEvents(
            withStart: startDate,
            end: endDate,
            calendars: nil
        )
        let events = eventStore.events(matching: predicate).prefix(limit)
        let items = events.map { event in
            [
                "title": event.title ?? "未命名日程",
                "start_date": iso8601String(from: event.startDate),
                "end_date": iso8601String(from: event.endDate),
                "is_all_day": event.isAllDay,
                "location": event.location ?? "",
                "calendar": event.calendar.title
            ] as [String: Any]
        }

        return [
            "range_start": iso8601String(from: startDate),
            "range_end": iso8601String(from: endDate),
            "count": items.count,
            "events": items
        ]
    }

    /**
     * 确保已获得通讯录读取权限。
     *
     * @throws 通讯录权限被限制、拒绝或授权失败
     * @author xiangwei
     */
    private func ensureContactsAccess() async throws {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized, .limited:
            return
        case .notDetermined:
            let granted: Bool = try await withCheckedThrowingContinuation { continuation in
                contactStore.requestAccess(for: .contacts) { granted, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: granted)
                    }
                }
            }
            guard granted else {
                throw LocalToolError.permissionDenied("通讯录")
            }
        case .restricted, .denied:
            throw LocalToolError.permissionDenied("通讯录")
        @unknown default:
            throw LocalToolError.permissionUnavailable("通讯录")
        }
    }

    /**
     * 确保已获得日历完整访问权限。
     *
     * @throws 日历权限被限制、拒绝或授权失败
     * @author xiangwei
     */
    private func ensureCalendarAccess() async throws {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .authorized, .fullAccess:
            return
        case .notDetermined:
            let granted: Bool = try await withCheckedThrowingContinuation { continuation in
                eventStore.requestFullAccessToEvents { granted, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: granted)
                    }
                }
            }
            guard granted else {
                throw LocalToolError.permissionDenied("日历")
            }
        case .restricted, .denied, .writeOnly:
            throw LocalToolError.permissionDenied("日历")
        @unknown default:
            throw LocalToolError.permissionUnavailable("日历")
        }
    }

    /**
     * 确保已获得健康数据读取权限。
     *
     * @throws 健康权限被拒绝或设备不支持
     * @author xiangwei
     */
    private func ensureHealthAccess() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw LocalToolError.healthDataUnavailable("设备不支持健康数据")
        }

        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            throw LocalToolError.healthDataUnavailable("无法获取步数数据类型")
        }

        let status = healthStore.authorizationStatus(for: stepType)
        switch status {
        case .sharingAuthorized:
            return
        case .notDetermined:
            // requestAuthorization 不返回授权结论，必须在用户响应弹窗后再次查询授权状态
            try await healthStore.requestAuthorization(toShare: [], read: healthDataTypes)
            let newStatus = healthStore.authorizationStatus(for: stepType)
            guard newStatus == .sharingAuthorized else {
                throw LocalToolError.permissionDenied("健康")
            }
        case .sharingDenied:
            throw LocalToolError.permissionDenied("健康")
        @unknown default:
            throw LocalToolError.permissionUnavailable("健康")
        }
    }

    /**
     * 获取今日健康与运动数据。
     *
     * 查询步数、心率、静息心率、活动能量、步行距离和上一晚睡眠时长。
     *
     * @returns 健康数据汇总
     * @throws 权限不足或查询失败
     * @author xiangwei
     */
    private func healthInfo() async throws -> [String: Any] {
        try await ensureHealthAccess()

        let now = Date()
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: now)
        var result: [String: Any] = [:]

        // 步数（今日累计）
        if let steps = await statisticsSum(for: .stepCount, from: startOfDay, to: now, unit: .count()) {
            result["today_steps"] = Int(steps)
        }

        // 最近一次心率
        let bpmUnit = HKUnit(from: "count/min")
        if let heartRate = await latestQuantitySample(for: .heartRate, unit: bpmUnit) {
            result["latest_heart_rate_bpm"] = Int(heartRate)
        }

        // 最近一次静息心率
        if let restingRate = await latestQuantitySample(for: .restingHeartRate, unit: bpmUnit) {
            result["latest_resting_heart_rate_bpm"] = Int(restingRate)
        }

        // 活动能量（今日累计）
        if let energy = await statisticsSum(for: .activeEnergyBurned, from: startOfDay, to: now, unit: .kilocalorie()) {
            result["today_active_energy_kcal"] = Int(energy)
        }

        // 步行距离（今日累计）
        if let distance = await statisticsSum(for: .distanceWalkingRunning, from: startOfDay, to: now, unit: .meter()) {
            result["today_walking_distance_meters"] = Int(distance)
        }

        // 上一晚睡眠时长
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: startOfDay)!
        if let totalSleep = await sleepDuration(from: yesterdayStart, to: now) {
            result["last_sleep_duration_minutes"] = Int(totalSleep / 60)
        }

        result["data_date"] = iso8601String(from: now)

        return result
    }

    /**
     * 查询累计统计数据（步数、能量、距离等）。
     *
     * @param identifier 数据类型标识
     * @param start 查询起始时间
     * @param end 查询结束时间
     * @param unit 数据单位
     * @returns 累计值，查询失败时返回空
     * @author xiangwei
     */
    private func statisticsSum(
        for identifier: HKQuantityTypeIdentifier,
        from start: Date,
        to end: Date,
        unit: HKUnit
    ) async -> Double? {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else {
            return nil
        }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, error in
                guard let result, error == nil else {
                    continuation.resume(returning: nil)
                    return
                }
                let value = result.sumQuantity()?.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            healthStore.execute(query)
        }
    }

    /**
     * 查询最近一条数量样本（心率、静息心率等）。
     *
     * @param identifier 数据类型标识
     * @param unit 数据单位
     * @returns 最近一次采样值，查询失败时返回空
     * @author xiangwei
     */
    private func latestQuantitySample(
        for identifier: HKQuantityTypeIdentifier,
        unit: HKUnit
    ) async -> Double? {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else {
            return nil
        }

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                guard let sample = samples?.first as? HKQuantitySample, error == nil else {
                    continuation.resume(returning: nil)
                    return
                }
                let value = sample.quantity.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            healthStore.execute(query)
        }
    }

    /**
     * 查询睡眠时长。
     *
     * @param start 查询起始时间
     * @param end 查询结束时间
     * @returns 卧床总时长（秒），查询失败时返回空
     * @author xiangwei
     */
    private func sleepDuration(from start: Date, to end: Date) async -> TimeInterval? {
        guard let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else {
            return nil
        }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                guard let samples = samples as? [HKCategorySample], error == nil else {
                    continuation.resume(returning: nil)
                    return
                }
                let inBedSamples = samples.filter {
                    $0.value == HKCategoryValueSleepAnalysis.inBed.rawValue
                }
                let total = inBedSamples.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                continuation.resume(returning: total)
            }
            healthStore.execute(query)
        }
    }

    /**
     * 获取必填字符串参数。
     *
     * @param name 参数名
     * @param args 工具参数
     * @returns 去除首尾空格后的参数值
     * @throws 参数为空或不存在
     * @author xiangwei
     */
    private func requiredStringArgument(_ name: String, from args: [String: Any]) throws -> String {
        guard let value = args[name] as? String else {
            throw LocalToolError.invalidArgument(name)
        }
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedValue.isEmpty else {
            throw LocalToolError.invalidArgument(name)
        }
        return normalizedValue
    }

    /**
     * 获取限定范围的整数参数。
     *
     * @param name 参数名
     * @param args 工具参数
     * @param defaultValue 默认值
     * @param maximumValue 最大值
     * @returns 范围内的参数值
     * @author xiangwei
     */
    private func boundedIntegerArgument(
        _ name: String,
        from args: [String: Any],
        defaultValue: Int,
        maximumValue: Int
    ) -> Int {
        let value = (args[name] as? Int) ?? (args[name] as? NSNumber)?.intValue ?? defaultValue
        return min(max(value, 1), maximumValue)
    }

    /**
     * 将日期转为 ISO8601 文本。
     *
     * @param date 日期
     * @returns ISO8601 日期文本
     * @author xiangwei
     */
    private func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone.current
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    /**
     * 获取电池状态中文名称。
     *
     * @param state 电池状态
     * @returns 电池状态名称
     * @author xiangwei
     */
    private func batteryStateName(_ state: UIDevice.BatteryState) -> String {
        switch state {
        case .unknown:
            return "未知"
        case .unplugged:
            return "未充电"
        case .charging:
            return "充电中"
        case .full:
            return "已充满"
        @unknown default:
            return "未知"
        }
    }
}

/**
 * 单次定位请求。
 *
 * 负责系统权限状态变化和定位回调，并确保异步调用只结束一次。
 *
 * @author xiangwei
 */
@MainActor
private final class LocationRequest: NSObject, @MainActor CLLocationManagerDelegate {
    /// 系统定位管理器。
    private let manager = CLLocationManager()

    /// 等待定位结果的异步延续。
    private var continuation: CheckedContinuation<CLLocation, Error>?

    /// 当前定位精度授权名称。
    var accuracyAuthorizationName: String {
        switch manager.accuracyAuthorization {
        case .fullAccuracy:
            return "精确位置"
        case .reducedAccuracy:
            return "大致位置"
        @unknown default:
            return "未知"
        }
    }

    /**
     * 发起定位请求。
     *
     * @returns 当前定位
     * @throws 定位权限或定位执行异常
     * @author xiangwei
     */
    func start() async throws -> CLLocation {
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            handleAuthorizationStatus(manager.authorizationStatus)
        }
    }

    /**
     * 处理定位权限状态变化。
     *
     * @param manager 定位管理器
     * @author xiangwei
     */
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        handleAuthorizationStatus(manager.authorizationStatus)
    }

    /**
     * 处理定位成功回调。
     *
     * @param manager 定位管理器
     * @param locations 定位结果
     * @author xiangwei
     */
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            finish(with: .failure(LocalToolError.locationUnavailable))
            return
        }
        finish(with: .success(location))
    }

    /**
     * 处理定位失败回调。
     *
     * @param manager 定位管理器
     * @param error 定位异常
     * @author xiangwei
     */
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(with: .failure(error))
    }

    /**
     * 根据权限状态继续授权或定位。
     *
     * @param status 定位权限状态
     * @author xiangwei
     */
    private func handleAuthorizationStatus(_ status: CLAuthorizationStatus) {
        guard continuation != nil else { return }

        switch status {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .restricted, .denied:
            finish(with: .failure(LocalToolError.permissionDenied("定位")))
        @unknown default:
            finish(with: .failure(LocalToolError.permissionUnavailable("定位")))
        }
    }

    /**
     * 完成定位请求并释放回调。
     *
     * @param result 定位结果
     * @author xiangwei
     */
    private func finish(with result: Result<CLLocation, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        manager.stopUpdatingLocation()
        manager.delegate = nil
        continuation.resume(with: result)
    }
}

/**
 * 本机工具异常。
 *
 * @author xiangwei
 */
private enum LocalToolError: LocalizedError {
    /// 不支持的工具。
    case unsupportedTool(String)

    /// 参数无效。
    case invalidArgument(String)

    /// 系统权限被拒绝。
    case permissionDenied(String)

    /// 系统权限状态不可用。
    case permissionUnavailable(String)

    /// 无法获取定位。
    case locationUnavailable

    /// 无法计算日历查询范围。
    case calendarRangeUnavailable

    /// 健康数据查询失败。
    case healthDataUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedTool(let toolName):
            return "不支持的本机工具: \(toolName)"
        case .invalidArgument(let argumentName):
            return "工具参数 \(argumentName) 不能为空"
        case .permissionDenied(let permissionName):
            return "未获得\(permissionName)权限，请在系统设置的隐私与安全性中允许笔笔访问"
        case .permissionUnavailable(let permissionName):
            return "当前无法确认\(permissionName)权限状态"
        case .locationUnavailable:
            return "系统未返回有效定位，请确认定位服务可用后重试"
        case .calendarRangeUnavailable:
            return "无法计算日历查询时间范围"
        case .healthDataUnavailable(let detail):
            return "无法获取健康数据: \(detail)"
        }
    }
}
