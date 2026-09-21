import Foundation

enum ByteCount {
    /// "1.2 GB" or "88 MB", in the user's language.
    static func string(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .file)
    }

    /// "812,340", grouped the way the user's language does it.
    static func number(_ value: UInt64) -> String {
        Int64(clamping: value).formatted(.number)
    }
}
