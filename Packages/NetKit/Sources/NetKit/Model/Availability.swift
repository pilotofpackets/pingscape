/// A permission the app may need before a value can be read.
public enum Permission: String, Sendable, Codable, Hashable {
    case location
    case localNetwork
}

/// The state of one data point.
///
/// The UI shows a row only when there is something to show: a value, a
/// loading placeholder, a permission prompt or a retry. `none` means the value
/// does not exist on this device or does not apply (for example no IPv6 address
/// or no VPN), and the row is left out.
public enum Availability<Value: Sendable>: Sendable {
    case value(Value)
    case loading
    case needsPermission(Permission)
    case failed(String)
    case none

    public var value: Value? {
        if case .value(let value) = self { return value }
        return nil
    }
}

extension Availability: Codable where Value: Codable {
    private enum Kind: String, Codable { case value, loading, needsPermission, failed, none }
    private enum CodingKeys: String, CodingKey { case kind, value, permission, message }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .value: self = .value(try container.decode(Value.self, forKey: .value))
        case .loading: self = .loading
        case .needsPermission: self = .needsPermission(try container.decode(Permission.self, forKey: .permission))
        case .failed: self = .failed(try container.decode(String.self, forKey: .message))
        case .none: self = .none
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .value(let value):
            try container.encode(Kind.value, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .loading: try container.encode(Kind.loading, forKey: .kind)
        case .needsPermission(let permission):
            try container.encode(Kind.needsPermission, forKey: .kind)
            try container.encode(permission, forKey: .permission)
        case .failed(let message):
            try container.encode(Kind.failed, forKey: .kind)
            try container.encode(message, forKey: .message)
        case .none: try container.encode(Kind.none, forKey: .kind)
        }
    }
}

extension Availability: Equatable where Value: Equatable {}
extension Availability: Hashable where Value: Hashable {}
