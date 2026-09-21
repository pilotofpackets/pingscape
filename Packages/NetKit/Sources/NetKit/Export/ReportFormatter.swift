import Foundation

public struct ReportRow: Sendable, Equatable {
    public let label: String
    public let value: String
    /// Addresses and network names: replaced while values are hidden.
    public let isSensitive: Bool
    /// Raw text such as a Whois record: its line breaks stay, and a row without
    /// a label is just the text.
    public let isPreformatted: Bool

    public init(label: String, value: String, isSensitive: Bool, isPreformatted: Bool = false) {
        self.label = label
        self.value = value
        self.isSensitive = isSensitive
        self.isPreformatted = isPreformatted
    }
}

public struct ReportSection: Sendable, Equatable {
    public let title: String
    public let rows: [ReportRow]

    public init(title: String, rows: [ReportRow]) {
        self.title = title
        self.rows = rows
    }
}

/// Writes what the screen shows as plain text. A report holds only what the app
/// would show, nothing hidden, and it follows the "hide values" switch.
public enum ReportFormatter {
    /// What stands in for a hidden value. The same on screen and in a report.
    public static let placeholder = "•••••••"

    /// Header lines, then the sections. Rows without a value are left out.
    public static func text(header: [String], sections: [ReportSection], masked: Bool) -> String {
        var blocks: [String] = []
        if !header.isEmpty { blocks.append(header.joined(separator: "\n")) }
        for section in sections {
            let body = lines(of: section, masked: masked)
            if !body.isEmpty { blocks.append(section.title.uppercased() + "\n" + body) }
        }
        return blocks.joined(separator: "\n\n")
    }

    /// One section as `Label: Value` lines, without a heading (the copy of a
    /// single section adds its own).
    public static func lines(of section: ReportSection, masked: Bool) -> String {
        section.rows
            .filter { !$0.value.isEmpty }
            .map { row in
                let label = row.label
                let value = masked && row.isSensitive ? placeholder : row.value
                // Raw text keeps its lines. A row without a label is just the text.
                if row.isPreformatted { return label.isEmpty ? value : "\(label):\n\(value)" }
                // A value of several lines (DNS servers) stays on one line.
                let oneLine = value.split(whereSeparator: \.isNewline).joined(separator: ", ")
                return "\(label): \(oneLine)"
            }
            .joined(separator: "\n")
    }

    /// A heading and the lines, for "Copy section".
    public static func text(of section: ReportSection, masked: Bool) -> String {
        let body = lines(of: section, masked: masked)
        return body.isEmpty ? section.title : section.title.uppercased() + "\n" + body
    }

    /// A row value as a CSV field (RFC 4180): quoted if it holds a comma, a
    /// quote or a line break.
    static func csvField(_ text: String) -> String {
        guard text.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return text }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

/// The list of devices on the local network as text and as CSV.
public enum LANReport {
    /// `192.0.2.40 · Living Room TV · AirPlay, HomeKit · 4 ms`, one line per device.
    /// Names and addresses are replaced while values are hidden.
    public static func text(_ devices: [LANDevice], masked: Bool) -> String {
        devices.map { device in
            var parts = [masked ? ReportFormatter.placeholder : device.ip]
            if let name = device.displayName { parts.append(masked ? ReportFormatter.placeholder : name) }
            let services = serviceNames(device)
            if !services.isEmpty { parts.append(services.joined(separator: ", ")) }
            if let latency = device.latencyMilliseconds { parts.append(String(format: "%.0f ms", latency)) }
            return parts.joined(separator: " · ")
        }.joined(separator: "\n")
    }

    public static func csv(_ devices: [LANDevice], masked: Bool) -> String {
        let placeholder = ReportFormatter.placeholder
        var lines = ["ip,name,services,latency_ms"]
        for device in devices {
            let fields = [
                masked ? placeholder : device.ip,
                masked ? (device.displayName == nil ? "" : placeholder) : device.displayName ?? "",
                serviceNames(device).joined(separator: " "),
                device.latencyMilliseconds.map { String(format: "%.1f", $0) } ?? "",
            ]
            lines.append(fields.map(ReportFormatter.csvField).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// The service types without `_` and the transport: `_airplay._tcp` is `airplay`.
    public static func serviceNames(_ device: LANDevice) -> [String] {
        var seen = Set<String>()
        return device.services.compactMap { service in
            let name = service.type.split(separator: ".").first.map { String($0.dropFirst()) } ?? service.type
            return seen.insert(name).inserted ? name : nil
        }
    }
}
