#if os(Windows)
import Foundation

enum WindowsSIwebSessionInputError: Error, Equatable, CustomStringConvertible {
    case empty
    case tooLarge
    case malformed

    var description: String {
        switch self {
        case .empty: "SIweb session is empty"
        case .tooLarge: "SIweb session is too large for secure storage"
        case .malformed: "SIweb session must contain only cookie name=value pairs"
        }
    }
}

/// Validates the value of an HTTP Cookie request header before it reaches
/// Credential Manager. Passwords, authorization headers, and whole requests
/// are intentionally rejected.
struct WindowsSIwebSessionInput {
    static let maximumUTF8Bytes = 2_400

    func normalize(_ rawValue: String) throws -> String {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw WindowsSIwebSessionInputError.empty }
        guard value.utf8.count <= Self.maximumUTF8Bytes else {
            throw WindowsSIwebSessionInputError.tooLarge
        }
        guard value.rangeOfCharacter(from: .newlines) == nil,
              !value.lowercased().hasPrefix("cookie:"),
              !value.lowercased().hasPrefix("authorization:")
        else { throw WindowsSIwebSessionInputError.malformed }

        let allowedName = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "!#$%&'*+-.^_`|~")
        )
        var normalized: [String] = []
        var names = Set<String>()

        for component in value.split(separator: ";", omittingEmptySubsequences: false) {
            let pair = component.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2 else { throw WindowsSIwebSessionInputError.malformed }
            let name = String(pair[0]).trimmingCharacters(in: .whitespaces)
            let cookieValue = String(pair[1]).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !cookieValue.isEmpty,
                  name.unicodeScalars.allSatisfy({ allowedName.contains($0) }),
                  cookieValue.unicodeScalars.allSatisfy({ scalar in
                      scalar.value >= 0x21 && scalar.value <= 0x7E && scalar.value != 0x3B
                  }),
                  names.insert(name).inserted
            else { throw WindowsSIwebSessionInputError.malformed }
            normalized.append("\(name)=\(cookieValue)")
        }
        return normalized.joined(separator: "; ")
    }
}
#endif
