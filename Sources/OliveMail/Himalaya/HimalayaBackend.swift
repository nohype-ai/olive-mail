import Foundation
#if canImport(System)
import System
#else
import SystemPackage
#endif

struct HimalayaBackend: MailBackend {
    let paths: FilePaths
    let invoke: @Sendable ([String]) async throws -> Data

    init(
        paths: FilePaths,
        invoke: (@Sendable ([String]) async throws -> Data)? = nil
    ) {
        self.paths = paths
        let config = paths.himalayaConfig
        self.invoke = invoke ?? { args in
            try await Himalaya.run(config: config, arguments: args)
        }
    }

    func listMailboxes() async throws -> [Mailbox.Info] {
        let data = try await invoke(["mailbox", "list"])
        let decoded = try Himalaya.decode(MailboxList.self, from: data)
        return decoded.mailboxes.map { Mailbox.Info(id: $0.id, name: $0.name) }
    }
}

private struct MailboxList: Decodable {
    var mailboxes: [Item]
    struct Item: Decodable {
        var id: String
        var name: String
    }
}
