#if canImport(System)
import System
#else
import SystemPackage
#endif

enum OliveMailError: Error, Equatable, CustomStringConvertible {
    case missingHome
    case missingEmail
    case emptyEmail
    case missingImap
    case emptyImap
    case emptyPassword
    case passwordsMismatch
    case missingConfig(FilePath)
    case missingPassword(FilePath)
    case missingHimalaya
    case himalayaFailed(String)
    case himalayaJSON(String)

    var description: String {
        switch self {
        case .missingHome:
            "olive-mail: HOME is not set"
        case .missingEmail:
            "olive-mail account add: email required"
        case .emptyEmail:
            "olive-mail account add: empty email"
        case .missingImap:
            "olive-mail account add: --imap required when not a tty"
        case .emptyImap:
            "olive-mail account add: empty IMAP server"
        case .emptyPassword:
            "olive-mail account add: empty password"
        case .passwordsMismatch:
            "olive-mail account add: passwords did not match"
        case .missingConfig(let path):
            "olive-mail: no config at \(path). Run: olive-mail account add"
        case .missingPassword(let dir):
            "olive-mail: no app password in \(dir). Run: olive-mail account add"
        case .missingHimalaya:
            "olive-mail: himalaya not found. Install: brew install himalaya"
        case .himalayaFailed(let message):
            "olive-mail: \(message)"
        case .himalayaJSON(let message):
            "olive-mail: could not parse himalaya JSON (\(message))"
        }
    }
}
