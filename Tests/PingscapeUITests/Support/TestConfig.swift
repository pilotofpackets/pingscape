import XCTest

/// The variant a test run covers: language, text size, appearance, orientation.
///
/// Read from the environment, so one build runs in every variant.
/// `xcodebuild` hands `TEST_RUNNER_PS_TEXT_SIZE=AX5` to the runner as
/// `PS_TEXT_SIZE=AX5` (see scripts/ui-matrix.sh). Without any of them, a run
/// from Xcode uses English, the default text size, light mode and portrait.
struct TestConfig: CustomStringConvertible {
    /// `en`, `de`, `fr`, `es` or `it`.
    var language: String
    var textSize: TextSize
    var dark: Bool
    var landscape: Bool
    /// Starts with "Hide values by default" on.
    var hideValues: Bool
    /// Runs the accessibility audit on every screen.
    var audit: Bool
    /// Which checks of the audit run. `PS_AUDIT_TYPES=contrast,hit` for a subset.
    var auditTypes: XCUIAccessibilityAuditType
    /// Most pages a screen check scrolls through.
    var maxPages: Int
    /// Wait after a launch or scroll before the checks.
    var settleSeconds: Double

    static let current = TestConfig(environment: ProcessInfo.processInfo.environment)

    init(environment: [String: String]) {
        language = environment["PS_LANGUAGE"] ?? "en"
        textSize = environment["PS_TEXT_SIZE"].flatMap(TextSize.init(rawValue:)) ?? .L
        dark = environment["PS_APPEARANCE"] == "dark"
        landscape = environment["PS_ORIENTATION"] == "landscape"
        hideValues = environment["PS_HIDE_VALUES"] == "1"
        audit = environment["PS_AUDIT"] != "0"
        auditTypes = environment["PS_AUDIT_TYPES"].map(Self.auditTypes(from:)) ?? .all
        maxPages = environment["PS_MAX_PAGES"].flatMap(Int.init) ?? 10
        settleSeconds = environment["PS_SETTLE"].flatMap(Double.init) ?? 1.5
    }

    static func auditTypes(from text: String) -> XCUIAccessibilityAuditType {
        let names: [String: XCUIAccessibilityAuditType] = [
            "contrast": .contrast, "dynamic": .dynamicType, "clip": .textClipped, "hit": .hitRegion,
            "element": .elementDetection, "description": .sufficientElementDescription, "trait": .trait,
        ]
        return text.split(separator: ",").reduce(into: []) { types, name in
            if let type = names[String(name)] { types.insert(type) }
        }
    }

    /// The same variant in English, for flows that find controls by their title.
    var english: TestConfig {
        var copy = self
        copy.language = "en"
        return copy
    }

    /// `en-L-light-portrait`, the folder name of the screenshots.
    var description: String {
        [language, textSize.rawValue, dark ? "dark" : "light", landscape ? "landscape" : "portrait"]
            .joined(separator: "-") + (hideValues ? "-hidden" : "")
    }

    /// The region that goes with the language, so numbers and dates are formatted like there.
    var locale: String {
        switch language {
        case "de": "de_DE"
        case "fr": "fr_FR"
        case "es": "es_ES"
        case "it": "it_IT"
        default: "en_US"
        }
    }
}

/// The text sizes of Settings › Display & Brightness › Text Size, and the
/// five larger accessibility sizes.
enum TextSize: String, CaseIterable {
    case XS, S, M, L, XL, XXL, XXXL, AX1, AX2, AX3, AX4, AX5

    /// The value of `-UIPreferredContentSizeCategoryName`.
    var category: String {
        switch self {
        case .XS: "UICTContentSizeCategoryXS"
        case .S: "UICTContentSizeCategoryS"
        case .M: "UICTContentSizeCategoryM"
        case .L: "UICTContentSizeCategoryL"
        case .XL: "UICTContentSizeCategoryXL"
        case .XXL: "UICTContentSizeCategoryXXL"
        case .XXXL: "UICTContentSizeCategoryXXXL"
        case .AX1: "UICTContentSizeCategoryAccessibilityM"
        case .AX2: "UICTContentSizeCategoryAccessibilityL"
        case .AX3: "UICTContentSizeCategoryAccessibilityXL"
        case .AX4: "UICTContentSizeCategoryAccessibilityXXL"
        case .AX5: "UICTContentSizeCategoryAccessibilityXXXL"
        }
    }

    var isAccessibilitySize: Bool { rawValue.hasPrefix("AX") }
}
