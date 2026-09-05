import Foundation
#if canImport(System)
import System
#else
import SystemPackage
#endif

/// `~/.config/olive-mail/` (or `$XDG_CONFIG_HOME/olive-mail/`).
/// `config.toml` is Himalaya’s config; `<email>.pass` is ours.
struct Paths: Equatable, Sendable {
    let directory: FilePath

    var himalayaConfig: FilePath {
        directory.appending("config.toml")
    }

    func passFile(email: String) -> FilePath {
        directory.appending("\(email).pass")
    }

    static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> Paths {
        let configHome: FilePath
        if let xdg = environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            configHome = FilePath(xdg)
        } else if let home = environment["HOME"], !home.isEmpty {
            configHome = FilePath(home).appending(".config")
        } else {
            throw OliveMailError.missingHome
        }
        return Paths(directory: configHome.appending("olive-mail"))
    }
}

enum OliveMailError: Error, Equatable, CustomStringConvertible {
    case missingHome

    var description: String {
        switch self {
        case .missingHome:
            "olive-mail: HOME is not set"
        }
    }
}
