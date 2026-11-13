import Foundation
import Testing

/// The string catalogs: every string in all five languages, translated,
/// with the same placeholders as the English one.
@Suite("String catalogs")
struct LocalizationTests {
    static let languages = ["de", "fr", "es", "it"]
    static let catalogs = ["Localizable", "InfoPlist", "AppShortcuts"]

    /// The repository, from this file: Tests/PingscapeTests/LocalizationTests.swift.
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()

    struct Entry {
        let key: String
        let source: [String]
        /// Language → every text of it (several for plural or device variations).
        let translations: [String: [String]]
        let states: [String: [String]]
        let isStale: Bool
    }

    static func entries(of catalog: String) throws -> [Entry] {
        let url = root.appending(path: "App/Resources/\(catalog).xcstrings")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        let strings = json["strings"] as? [String: [String: Any]] ?? [:]
        return strings.compactMap { key, value in
            if value["shouldTranslate"] as? Bool == false { return nil }
            let localizations = value["localizations"] as? [String: Any] ?? [:]
            var texts: [String: [String]] = [:]
            var states: [String: [String]] = [:]
            for (language, localization) in localizations {
                let units = Self.units(in: localization)
                texts[language] = units.map(\.value)
                states[language] = units.map(\.state)
            }
            return Entry(
                key: key, source: texts["en"] ?? [key], translations: texts, states: states,
                isStale: value["extractionState"] as? String == "stale")
        }
        .sorted { $0.key < $1.key }
    }

    /// Every `stringUnit` and `stringSet` of a localization, also inside plural and device variations.
    static func units(in node: Any) -> [(value: String, state: String)] {
        guard let node = node as? [String: Any] else { return [] }
        var found: [(String, String)] = []
        if let unit = node["stringUnit"] as? [String: Any] {
            found.append((unit["value"] as? String ?? "", unit["state"] as? String ?? ""))
        }
        // Siri phrases: several ways to say one shortcut.
        if let set = node["stringSet"] as? [String: Any] {
            let state = set["state"] as? String ?? ""
            found += (set["values"] as? [String] ?? []).map { ($0, state) }
        }
        if let variations = node["variations"] as? [String: Any] {
            for (_, kind) in variations {
                for (_, variant) in (kind as? [String: Any] ?? [:]) { found += units(in: variant) }
            }
        }
        if let substitutions = node["substitutions"] as? [String: Any] {
            for (_, substitution) in substitutions { found += units(in: substitution) }
        }
        return found
    }

    /// `%@`, `%lld`, `%1$@`, … as types, order ignored (a translation may move them).
    static func placeholders(_ text: String) -> [String] {
        let pattern = try! NSRegularExpression(pattern: #"%(\d+\$)?[-+ 0#]*\d*(\.\d+)?(ll|l|h|hh|q|z|t|j)?([@dDuUxXoOfFeEgGcCsSaAp%])"#)
        return pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            let length = Range(match.range(at: 3), in: text).map { String(text[$0]) } ?? ""
            guard let type = Range(match.range(at: 4), in: text).map({ String(text[$0]) }), type != "%" else { return nil }
            return length + type
        }
        .sorted()
    }

    @Test("Every string is translated into every language", arguments: catalogs)
    func complete(_ catalog: String) throws {
        for entry in try Self.entries(of: catalog) where !entry.isStale {
            for language in Self.languages {
                let texts = entry.translations[language] ?? []
                #expect(!texts.isEmpty, "\(catalog): “\(entry.key)” has no \(language)")
                #expect(texts.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty }, "\(catalog): “\(entry.key)” is empty in \(language)")
                let open = (entry.states[language] ?? []).filter { $0 != "translated" }
                #expect(open.isEmpty, "\(catalog): “\(entry.key)” in \(language) is \(open.joined(separator: ", "))")
            }
        }
    }

    @Test("Translations have the placeholders of the English text", arguments: catalogs)
    func placeholdersMatch(_ catalog: String) throws {
        for entry in try Self.entries(of: catalog) where !entry.isStale {
            let sourceSets = Set(entry.source.map(Self.placeholders))
            let allowed = Set(sourceSets.flatMap { $0 })
            let isPlural = entry.source.count > 1
            for (language, texts) in entry.translations where language != "en" {
                for text in texts {
                    let found = Self.placeholders(text)
                    if isPlural || texts.count > 1 {
                        // A plural form may leave the number out ("one byte"), but not add one.
                        #expect(Set(found).isSubset(of: allowed), "\(catalog) \(language): “\(text)” for “\(entry.key)”")
                    } else {
                        #expect(sourceSets.contains(found), "\(catalog) \(language): “\(text)” has \(found), English has \(sourceSets.first ?? [])")
                    }
                }
            }
        }
    }

    @Test("No leftover strings the code no longer uses", arguments: catalogs)
    func noStaleEntries(_ catalog: String) throws {
        let stale = try Self.entries(of: catalog).filter(\.isStale).map(\.key)
        #expect(stale.isEmpty, "\(catalog): \(stale.count) stale: \(stale.prefix(20).joined(separator: " | "))")
    }

    @Test("A translation is not just the English text again", arguments: languages)
    func notCopied(_ language: String) throws {
        // Names, units and technical terms are the same in every language.
        let same = try Self.entries(of: "Localizable").filter { entry in
            guard !entry.isStale, let texts = entry.translations[language], texts == entry.source else { return false }
            let text = entry.source.joined()
            let words = text.split(whereSeparator: { !$0.isLetter }).filter { $0.count > 3 }
            return words.count >= 3
        }
        .map(\.key)
        #expect(same.isEmpty, "\(language) has \(same.count) strings that are the English text: \(same.prefix(15).joined(separator: " | "))")
    }

    @Test("Placeholders are found")
    func placeholderParsing() {
        #expect(Self.placeholders("%lld bytes") == ["lld"])
        #expect(Self.placeholders("%1$@ to %2$@, 100%%") == ["@", "@"])
        #expect(Self.placeholders("no placeholder") == [])
    }
}
