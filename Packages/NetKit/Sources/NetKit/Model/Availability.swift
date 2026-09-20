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

extension Availability: Equatable where Value: Equatable {}
extension Availability: Hashable where Value: Hashable {}
