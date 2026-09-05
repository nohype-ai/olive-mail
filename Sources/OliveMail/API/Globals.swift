import ArgumentParser
import Foundation

struct Globals: ParsableArguments {
    // MVP: no multi-account
    // @Option(name: .shortAndLong, help: "Account. Omitted: all accounts.")
    // var account: String?

    @Flag(help: "JSON output.")
    var json = false
}

func printJSON(_ value: some Encodable) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    var data = try encoder.encode(value)
    data.append(contentsOf: "\n".utf8)
    FileHandle.standardOutput.write(data)
}
