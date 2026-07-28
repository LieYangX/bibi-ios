import Foundation

/**
 * 通用 JSON Codable 包装类型
 *
 * 用于编码和解码任意 JSON 值（字符串、数字、布尔值、数组、字典、null）。
 * PC 端工具返回的结果可能为任意 JSON 结构，使用此类型可避免类型丢失。
 *
 * @author xiangwei
 */
struct AnyCodable: Codable {
    /// 底层 JSON 值
    let value: Any

    /**
     * 使用任意值初始化
     *
     * @param value 任意 JSON 可表示的值
     */
    init(_ value: Any) {
        self.value = value
    }

    /**
     * 从 Decoder 解码
     *
     * 先解码为原始 JSON 字符串，再用 JSONSerialization 解析为任意值。
     */
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let string = try? container.decode(String.self) {
            value = string
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            value = dictionary.mapValues { $0.value }
        } else if container.decodeNil() {
            value = NSNull()
        } else {
            value = NSNull()
        }
    }

    /**
     * 编码到 Encoder
     *
     * 使用 JSONSerialization 将任意值序列化后再编码。
     */
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        if value is NSNull {
            try container.encodeNil()
            return
        }

        let data = try JSONSerialization.data(withJSONObject: value, options: [])
        let jsonObject = try JSONSerialization.jsonObject(with: data)

        try encodeValue(jsonObject, into: &container)
    }

    /**
     * 递归编码单个值
     */
    private func encodeValue(_ value: Any, into container: inout SingleValueEncodingContainer) throws {
        switch value {
        case let string as String:
            try container.encode(string)
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let array as [Any]:
            let wrapped = array.map { AnyCodable($0) }
            try container.encode(wrapped)
        case let dictionary as [String: Any]:
            let wrapped = dictionary.mapValues { AnyCodable($0) }
            try container.encode(wrapped)
        default:
            try container.encode(String(describing: value))
        }
    }
}
