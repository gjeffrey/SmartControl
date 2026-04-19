import Foundation

enum JSONValue: Hashable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(any value: Any) {
        switch value {
        case let dictionary as [String: Any]:
            self = .object(dictionary.mapValues(JSONValue.init(any:)))
        case let array as [Any]:
            self = .array(array.map(JSONValue.init(any:)))
        case let string as String:
            self = .string(string)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else {
                self = .number(number.doubleValue)
            }
        default:
            self = .null
        }
    }

    static func decode(data: Data) throws -> JSONValue {
        let object = try JSONSerialization.jsonObject(with: data)
        return JSONValue(any: object)
    }

    subscript(_ key: String) -> JSONValue? {
        guard case let .object(dictionary) = self else {
            return nil
        }

        return dictionary[key]
    }

    subscript(index: Int) -> JSONValue? {
        guard case let .array(values) = self, values.indices.contains(index) else {
            return nil
        }

        return values[index]
    }

    func value(at path: [String]) -> JSONValue? {
        path.reduce(Optional(self)) { partial, key in
            partial.flatMap { $0[key] }
        }
    }

    var objectValue: [String: JSONValue]? {
        guard case let .object(dictionary) = self else {
            return nil
        }

        return dictionary
    }

    var arrayValue: [JSONValue]? {
        guard case let .array(array) = self else {
            return nil
        }

        return array
    }

    var stringValue: String? {
        switch self {
        case let .string(value):
            return value
        case let .number(value):
            return value.rounded(.towardZero) == value ? String(Int(value)) : String(value)
        case let .bool(value):
            return value ? "true" : "false"
        default:
            return nil
        }
    }

    var doubleValue: Double? {
        switch self {
        case let .number(value):
            return value
        case let .string(value):
            return Double(value)
        default:
            return nil
        }
    }

    var intValue: Int? {
        guard let value = doubleValue else {
            return nil
        }

        return Int(value)
    }

    var boolValue: Bool? {
        switch self {
        case let .bool(value):
            return value
        case let .string(value):
            return Bool(value)
        default:
            return nil
        }
    }
}
