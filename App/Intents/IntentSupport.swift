import AppIntents
import Foundation
import NetKit

// Shared by the Shortcuts actions: errors as one readable sentence, the
// target of a tool, and the "Hide values" setting for what Siri says.

/// A failure as the sentence Siri says and Shortcuts shows.
struct IntentMessage: Error, CustomLocalizedStringResourceConvertible {
    let text: String

    init(_ text: String) { self.text = text }

    /// The same wording as the tools in the app.
    init(_ error: any Error, target: ResolvedAddress? = nil) {
        switch error {
        case let message as IntentMessage: text = message.text
        case let failure as ToolFailure: text = failure.text
        case let tool as ToolError: text = ToolFailure.from(tool, target: target).text
        case let input as InputError: text = input.text
        default: text = error.localizedDescription
        }
    }

    var localizedStringResource: LocalizedStringResource { LocalizedStringResource(stringLiteral: text) }
}

enum IntentSupport {
    static func snapshot() async -> NetworkSnapshot {
        await LiveSnapshotProvider(locationAuthorized: { LocationAccess.isAuthorized }).snapshot()
    }

    /// "Hide values by default" from About. Siri reads its answer aloud and shows
    /// it on the Lock Screen, so sensitive values are left out of the dialog
    /// then. The value handed to the shortcut stays real, as Copy does in the app.
    static var hidesValues: Bool { UserDefaults.standard.bool(forKey: PrivacyMask.hideByDefaultKey) }

    static func shown(_ value: String, sensitive: Bool) -> String {
        sensitive && hidesValues ? PrivacyMask.placeholder : value
    }

    /// External requests (public address, provider) are off until the user agrees.
    static var allowsExternalRequests: Bool { UserDefaults.standard.bool(forKey: AppSettings.externalLookupsKey) }

    /// A host name or address as typed, and the first address it resolves to.
    static func target(_ text: String) async throws -> (name: String, address: ResolvedAddress) {
        do {
            let name = try ToolInput.host(text)
            guard let address = try await HostResolver.resolve(name).first else { throw ToolError.cannotResolve }
            return (name, address)
        } catch {
            throw IntentMessage(error)
        }
    }

    static func dialog(_ text: String) -> IntentDialog { IntentDialog(stringLiteral: text) }
}
