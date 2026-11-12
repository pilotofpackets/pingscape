import XCTest

/// The checks every screen goes through, page by page down to its end:
///
/// - a screenshot, kept in the result bundle (scripts/ui-matrix.sh exports them),
/// - Apple's accessibility audit: contrast, Dynamic Type, clipped text, hit
///   regions, missing labels, wrong traits,
/// - no text or control that runs past the left or right edge of the window,
/// - the app is still running.
@MainActor
struct ScreenCheck {
    let test: XCTestCase
    let app: XCUIApplication
    let config: TestConfig

    /// Containers that scroll sideways on purpose. What sticks out of them is fine.
    static let horizontalScrollers: Set<String> = ["tool.chips", "tool.recent"]

    /// Checks the screen `name`, scrolling down until nothing moves any more.
    func run(
        _ name: String, scroll: Bool = true, maxPages: Int? = nil, file: StaticString = #filePath, line: UInt = #line
    ) {
        settle()
        var lastFingerprint: String?
        for page in 0..<(scroll ? min(maxPages ?? config.maxPages, config.maxPages) : 1) {
            guard let snapshot = try? app.snapshot() else {
                XCTFail("\(name): no accessibility snapshot", file: file, line: line)
                return
            }
            let fingerprint = Self.fingerprint(snapshot)
            if fingerprint == lastFingerprint { break }
            lastFingerprint = fingerprint

            attachScreenshot("\(name) \(page + 1)")
            checkEdges(snapshot, screen: name, page: page + 1, file: file, line: line)
            if config.audit { audit(screen: name, page: page + 1, seen: snapshot, file: file, line: line) }
            if scroll { app.scrollPage() ; settle() }
        }
        XCTAssertEqual(app.state, .runningForeground, "\(name): the app is no longer running", file: file, line: line)
    }

    /// Lets animations and the first load finish.
    func settle() {
        _ = app.wait(for: .runningForeground, timeout: 1)
        // Long enough for the scroll indicator to fade out.
        RunLoop.current.run(until: Date().addingTimeInterval(TimeInterval(config.settleSeconds)))
    }

    func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "\(config) · \(name)"
        attachment.lifetime = .keepAlways
        test.add(attachment)
    }

    // MARK: Accessibility audit

    private func audit(screen: String, page: Int, seen: XCUIElementSnapshot, file: StaticString, line: UInt) {
        let bars = glassAreas()
        let window = app.windows.firstMatch.frame
        let shown = Self.frames(in: seen, visibleIn: window)
        let screenshot = XCUIScreen.main.screenshot()
        // In landscape the simulator's screenshots are unreliable: on the iPad
        // mini ours had landscape size but the content half a screen down under
        // black, and the audit's own crop of an element came out rotated, so
        // "Details" (5.5:1 in portrait) measured 1.0–1.8:1 (2026-11-12). The
        // colors are the same in both orientations and judged in portrait.
        let pixelsMatch = !config.landscape && screenshotMatchesWindow(screenshot)
        let pixels = pixelsMatch ? PixelContrast(screenshot) : nil
        if !pixelsMatch {
            XCTContext.runActivity(named: "\(screen) page \(page): landscape or rotated screenshot, contrast is only a warning here") { _ in }
        }
        // One audit per kind of check. All kinds in one call never returned on
        // the iPhone SE (iOS 27) on some pages, while each kind alone took a
        // second or two (found 2026-11-11).
        for type in AuditVerdict.kinds where config.auditTypes.contains(type) {
            if let hang = AuditVerdict.knownHangs.first(where: { $0.screen == screen && $0.page == page && $0.type == type }) {
                XCTContext.runActivity(named: "\(screen) page \(page): \(AuditVerdict.name(of: type)) audit skipped, \(hang.why)") { _ in }
                continue
            }
            audit(
                type, screen: screen, page: page, pixelsMatch: pixelsMatch, pixels: pixels, bars: bars, window: window,
                shown: shown, file: file, line: line)
        }
    }

    private func audit(
        _ type: XCUIAccessibilityAuditType, screen: String, page: Int, pixelsMatch: Bool, pixels: PixelContrast?,
        bars: [CGRect], window: CGRect, shown: [String: [CGRect]],
        file: StaticString, line: UInt
    ) {
        do {
            try app.performAccessibilityAudit(for: type) { issue in
                // The element itself, not `snapshot()` of it: taking the
                // snapshot inside the audit's handler never returned on the
                // iPhone SE on some pages (2026-11-11).
                let element: (any XCUIElementAttributes)? = issue.element
                var verdict = AuditVerdict(issue, element: element, config: config, bars: bars, window: window)
                if !pixelsMatch, issue.auditType == .contrast, verdict == .failure { verdict = .warning }
                // The audit scrolls on its own and then measured rows of a
                // list mid-scroll as clipped, at places where the screenshot
                // showed other text (Siri phrases at AX5, 2026-11-12). Only
                // what was on screen, where it was, fails.
                var moved = false
                if issue.auditType == .textClipped, verdict == .failure, let element, !element.label.isEmpty {
                    let near = { (a: CGRect, b: CGRect) in abs(a.minY - b.minY) < 2 && abs(a.height - b.height) < 2 }
                    if !(shown[element.label] ?? []).contains(where: { near($0, element.frame) }) {
                        verdict = .warning
                        moved = true
                    }
                }
                // A second opinion from the pixels: below 4.5:1 there too, or it is only a warning.
                var measured: Double?
                if issue.auditType == .contrast, verdict == .failure, let element, let pixels {
                    measured = pixels.ratio(in: element.frame)
                    if let measured, measured >= 4.5 { verdict = .warning }
                }
                let text = """
                    Screen: \(screen), page \(page), \(config)
                    Verdict: \(verdict.title)
                    Type: \(AuditVerdict.name(of: issue.auditType))
                    Issue: \(issue.compactDescription)
                    Detail: \(issue.detailedDescription)
                    Element: \(element.map { "“\($0.label)” \($0.identifier)" } ?? "–")
                    Frame: \(element.map { "\($0.frame)" } ?? "–")
                    Measured: \(measured.map { String(format: "%.2f:1", $0) } ?? "–")
                    \(moved ? "Not where the screenshot showed it: the audit had scrolled." : "")
                    """
                XCTContext.runActivity(named: "\(verdict.title): \(screen) page \(page): \(issue.compactDescription)") { activity in
                    let attachment = XCTAttachment(string: text)
                    attachment.name = "Audit \(verdict.title)"
                    attachment.lifetime = verdict == .ignored ? .deleteOnSuccess : .keepAlways
                    activity.add(attachment)
                }
                // `false` makes XCTest record the issue as a failure.
                return verdict != .failure
            }
        } catch {
            XCTFail(
                "\(screen) page \(page): the \(AuditVerdict.name(of: type)) audit did not run: \(error)", file: file, line: line)
        }
    }

    /// The simulator's screenshot of a rotated iPad came out upright, half of
    /// it black, while the elements are in landscape. The audit measures
    /// contrast on those pixels, so there it measured nonsense.
    private func screenshotMatchesWindow(_ screenshot: XCUIScreenshot) -> Bool {
        let image = screenshot.image.size
        let window = app.windows.firstMatch.frame.size
        guard image.width > 0, window.width > 0 else { return true }
        return (image.width > image.height) == (window.width > window.height)
    }

    /// Where Liquid Glass lies over the content: the navigation bar with the
    /// blurred edge below it, the tab bar, and the floating Start and Done
    /// buttons. Text that scrolls under them is measured against the blur, so
    /// what lies there is not judged (it is checked once scrolled into the open).
    private func glassAreas() -> [CGRect] {
        let window = app.windows.firstMatch.frame
        var areas: [CGRect] = []
        // The bar of the page on screen; other tabs keep theirs off screen.
        let bars = app.navigationBars.allElementsBoundByIndex.map(\.frame).filter { $0.intersects(window) && !$0.isEmpty }
        // Without a bar (a sheet), the status bar and its edge are still glass.
        let top = max(bars.map(\.maxY).max() ?? 0, 60) + 32
        areas.append(CGRect(x: window.minX, y: window.minY, width: window.width, height: top))
        // Above the tab bar the content fades into its glass like under the
        // top bar: a footer just above it measured 3.3:1 there and passed
        // one page further (2026-11-12).
        for bar in app.tabBars.allElementsBoundByIndex where !bar.frame.isEmpty {
            let frame = bar.frame
            areas.append(CGRect(x: frame.minX - 8, y: frame.minY - 40, width: frame.width + 16, height: frame.height + 56))
        }
        // The home indicator's strip, where a row is cut off by the screen's edge.
        areas.append(CGRect(x: window.minX, y: window.maxY - 40, width: window.width, height: 40))
        for identifier in ["tool.start", "keyboard.done"] {
            let element = app.element(identifier)
            if element.exists, !element.frame.isEmpty { areas.append(element.frame.insetBy(dx: -8, dy: -8)) }
        }
        return areas
    }

    // MARK: Edges

    /// Text and controls that are partly on screen must fit in it sideways.
    /// Fully off-screen elements are ignored (pages of a paged view), and so
    /// is anything inside a container that scrolls sideways on purpose.
    private func checkEdges(_ root: XCUIElementSnapshot, screen: String, page: Int, file: StaticString, line: UInt) {
        let window = app.windows.firstMatch.frame
        guard window.width > 0 else { return }
        let checked: Set<XCUIElement.ElementType> = [.staticText, .button, .textField, .switch, .link, .segmentedControl]
        var problems: [String] = []

        func visit(_ element: XCUIElementSnapshot, insideScroller: Bool) {
            let scroller = insideScroller || Self.horizontalScrollers.contains(element.identifier)
            let frame = element.frame
            if !scroller, checked.contains(element.elementType), frame.width > 1, frame.height > 1,
                frame.intersects(window)
            {
                let tolerance: CGFloat = 1
                if frame.minX < window.minX - tolerance || frame.maxX > window.maxX + tolerance {
                    problems.append(
                        "“\(element.label.prefix(60))” (\(element.elementType.rawValue)) x \(Int(frame.minX))…\(Int(frame.maxX)), window \(Int(window.width)) wide"
                    )
                }
            }
            for child in element.children { visit(child, insideScroller: scroller) }
        }
        visit(root, insideScroller: false)

        for problem in problems {
            XCTFail("\(screen) page \(page) [\(config)]: sticks out of the window: \(problem)", file: file, line: line)
        }
    }

    /// The frames of the elements on screen, by label.
    static func frames(in root: XCUIElementSnapshot, visibleIn window: CGRect) -> [String: [CGRect]] {
        var frames: [String: [CGRect]] = [:]
        func visit(_ element: XCUIElementSnapshot) {
            if !element.label.isEmpty, element.frame.intersects(window) {
                frames[element.label, default: []].append(element.frame)
            }
            element.children.forEach(visit)
        }
        visit(root)
        return frames
    }

    /// What is on screen, to tell whether a scroll moved anything. Built from
    /// the elements, not the pixels: the clock in the status bar changes.
    static func fingerprint(_ root: XCUIElementSnapshot) -> String {
        var parts: [String] = []
        func visit(_ element: XCUIElementSnapshot) {
            if element.elementType == .staticText || element.elementType == .button {
                parts.append("\(element.label)@\(Int(element.frame.minY))")
            }
            element.children.forEach(visit)
        }
        visit(root)
        return parts.joined(separator: "|")
    }
}

/// How much an audit finding counts.
///
/// - failure: fails the test. Too little contrast, too small a tap target, a
///   missing label, a wrong trait, and text that is clipped at the size the
///   run actually uses (the accessibility sizes).
/// - warning: listed in the report, the test stays green. "Nearly" enough
///   contrast (the system's secondary text color is just under 4.5:1), and
///   the audit's guesses about sizes this run does not use.
/// - ignored: not the app's to fix: system UI, or text under a glass bar.
enum AuditVerdict: Equatable {
    case failure, warning, ignored

    var title: String {
        switch self {
        case .failure: "issue"
        case .warning: "warning"
        case .ignored: "ignored"
        }
    }

    @MainActor
    init(
        _ issue: XCUIAccessibilityAuditIssue, element: (any XCUIElementAttributes)?, config: TestConfig, bars: [CGRect],
        window: CGRect? = nil
    ) {
        guard let element else {
            self = .ignored
            return
        }
        if [.statusBar, .keyboard, .key].contains(element.elementType) {
            self = .ignored
            return
        }
        let frame = element.frame
        if !frame.isEmpty, bars.contains(where: { $0.intersects(frame) }) {
            self = .ignored
            return
        }
        // Scrolled off the screen, above the bar (y −20 in landscape): there
        // are no pixels to measure. It is checked on the page where it shows.
        if issue.auditType == .contrast, !frame.isEmpty, let window, !window.insetBy(dx: -1, dy: -1).contains(frame) {
            self = .ignored
            return
        }
        let description = issue.compactDescription.lowercased()
        if Self.checkedByEye.contains(where: { issue.auditType == $0.type && element.label == $0.label }) {
            self = .ignored
            return
        }
        if issue.auditType == .sufficientElementDescription, Self.isAddressOrHost(element.label) {
            self = .ignored
            return
        }
        switch issue.auditType {
        case .contrast:
            self = description.contains("nearly") ? .warning : .failure
        case .dynamicType:
            self = .warning
        case .textClipped:
            // A one-line text field scrolls sideways while editing, like
            // Safari's address bar; a long entry cut off at rest is how iOS
            // draws it, and several lines would break Return to start.
            self = config.textSize.isAccessibilitySize && element.elementType != .textField ? .failure : .warning
        default:
            self = .failure
        }
    }

    /// "192.168.178.0/24", "fe80::1", "whois.iana.org", "3C:A6:2F:1B:D3:22".
    static func isAddressOrHost(_ label: String) -> Bool {
        let pattern = #"^[0-9A-Za-z]+([.:][0-9A-Za-z-]*)+(/\d{1,3})?$"#
        return label.range(of: pattern, options: .regularExpression) != nil && label.contains(where: { ".:".contains($0) })
    }

    /// Findings looked at in the screenshot and found fine. Each with why;
    /// keep this list short.
    static let checkedByEye: [(type: XCUIAccessibilityAuditType, label: String, why: String)] = [
        (.textClipped, "Share as file", "wraps onto two lines at AX5 and is fully visible (2026-11-11)"),
    ]

    /// Pages where one kind of Apple's audit never returns while the app is
    /// idle. Each cost five minutes per run; the same kinds of rows are
    /// checked on every other page. Keep this list short.
    static let knownHangs: [(screen: String, page: Int, type: XCUIAccessibilityAuditType, why: String)] = [
        ("Tools › NTP", 2, .contrast, "never returned on iPhone 17 Pro (iOS 27) in three runs, the other kinds pass (2026-11-12)"),
    ]

    /// Every kind of check the audit has on iOS, one at a time.
    static let kinds: [XCUIAccessibilityAuditType] = [
        .contrast, .elementDetection, .hitRegion, .sufficientElementDescription, .dynamicType, .textClipped, .trait,
    ]

    static func name(of type: XCUIAccessibilityAuditType) -> String {
        switch type {
        case .contrast: "contrast"
        case .dynamicType: "dynamic type"
        case .textClipped: "text clipped"
        case .hitRegion: "hit region"
        case .elementDetection: "element detection"
        case .sufficientElementDescription: "element description"
        case .trait: "trait"
        default: "type \(type.rawValue)"
        }
    }
}

@MainActor
extension XCTestCase {
    /// Launches at `start` and runs the screen checks on it.
    func checkScreen(
        _ name: String, _ start: Start, config: TestConfig = .current, scroll: Bool = true, maxPages: Int? = nil,
        wait: ((XCUIApplication) -> XCUIElement)? = nil, file: StaticString = #filePath, line: UInt = #line
    ) {
        let app = launch(start, config: config)
        let anchor = wait?(app) ?? app.navigationBars.firstMatch
        guard expect(anchor, "on \(name)", timeout: 15, file: file, line: line) else {
            ScreenCheck(test: self, app: app, config: config).attachScreenshot("\(name) (did not load)")
            return
        }
        ScreenCheck(test: self, app: app, config: config).run(name, scroll: scroll, maxPages: maxPages, file: file, line: line)
    }
}
