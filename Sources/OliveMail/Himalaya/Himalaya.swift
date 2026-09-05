import Foundation
#if canImport(System)
import System
#else
import SystemPackage
#endif

/// Run the `himalaya` binary with our config and `--json`.
enum Himalaya {
    static func run(config: FilePath, arguments: [String]) async throws -> Data {
        guard let binary = findExecutable("himalaya") else {
            throw OliveMailError.missingHimalaya
        }
        return try await run(
            executable: binary,
            arguments: ["-c", config.string, "--json"] + arguments
        )
    }

    static func findExecutable(
        _ name: String,
        path: String? = ProcessInfo.processInfo.environment["PATH"],
        extra: [String] = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/home/linuxbrew/.linuxbrew/bin",
        ]
    ) -> FilePath? {
        var dirs: [String] = []
        if let path {
            dirs.append(contentsOf: path.split(separator: ":").map(String.init))
        }
        dirs.append(contentsOf: extra)
        let fm = FileManager.default
        var seen = Set<String>()
        for dir in dirs where seen.insert(dir).inserted {
            let candidate = FilePath(dir).appending(name)
            if fm.isExecutableFile(atPath: candidate.string) {
                return candidate
            }
        }
        return nil
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        if let payload = try? JSONDecoder().decode(ErrorPayload.self, from: data),
           !payload.error.isEmpty {
            throw OliveMailError.himalayaFailed(payload.error)
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw OliveMailError.himalayaJSON(error.localizedDescription)
        }
    }

    private struct ErrorPayload: Decodable {
        var error: String
    }

    private static func run(executable: FilePath, arguments: [String]) async throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable.string)
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        let outTask = Task.detached { stdout.fileHandleForReading.readDataToEndOfFile() }
        let errTask = Task.detached { stderr.fileHandleForReading.readDataToEndOfFile() }
        process.waitUntilExit()
        let out = await outTask.value
        let err = await errTask.value
        if !err.isEmpty {
            FileHandle.standardError.write(err)
        }
        if process.terminationStatus != 0 {
            if let payload = try? JSONDecoder().decode(ErrorPayload.self, from: out) {
                throw OliveMailError.himalayaFailed(payload.error)
            }
            let message = String(data: err.isEmpty ? out : err, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw OliveMailError.himalayaFailed(
                message?.isEmpty == false ? message! : "himalaya exited \(process.terminationStatus)"
            )
        }
        return out
    }
}
