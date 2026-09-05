import Foundation
import Testing
#if canImport(System)
import System
#else
import SystemPackage
#endif
@testable import OliveMail

@Test func accountAddWritesConfigAndPass() throws {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let paths = FilePaths(directory: FilePath(tmp.path))
    try AccountStore.write(
        paths: paths,
        email: "you@example.com",
        imap: "imaps://imap.example.com:993",
        password: "s3cret"
    )

    let pass = paths.passFile(email: "you@example.com")
    let passData = try Data(contentsOf: URL(fileURLWithPath: pass.string))
    #expect(String(data: passData, encoding: .utf8) == "s3cret")

    let perms = try FileManager.default.attributesOfItem(atPath: pass.string)[.posixPermissions] as? Int
    #expect((perms ?? 0) & 0o777 == 0o600)

    let config = try String(
        contentsOf: URL(fileURLWithPath: paths.himalayaConfig.string),
        encoding: .utf8
    )
    #expect(!config.contains("s3cret"))
    #expect(config.contains("[accounts.\"you@example.com\"]"))
    #expect(config.contains("imaps://imap.example.com:993"))
    #expect(config.contains("/bin/cat"))
    #expect(config.contains(pass.string))
    #expect(!config.contains("smtp.server"))
    #expect(!config.contains("[smtp"))
}

@Test func requireConfiguredNeedsFiles() throws {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let paths = FilePaths(directory: FilePath(tmp.path))
    #expect(throws: OliveMailError.missingConfig(paths.himalayaConfig)) {
        try paths.requireConfigured()
    }

    try Data("# none\n".utf8).write(to: URL(fileURLWithPath: paths.himalayaConfig.string))
    #expect(throws: OliveMailError.missingPassword(paths.directory)) {
        try paths.requireConfigured()
    }
}
