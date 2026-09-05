import ArgumentParser
import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

struct Account: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Accounts.",
        subcommands: [
            Add.self,
            // List.self, // MVP: no multi-account
        ]
    )

    struct Add: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Add an account (IMAP credentials)."
        )

        @Argument(help: "Email address.")
        var email: String?

        @Option(help: "IMAP server URL (e.g. imaps://imap.example.com:993).")
        var imap: String?

        mutating func run() async throws {
            let tty = isatty(FileHandle.standardInput.fileDescriptor) != 0
            var email = self.email ?? ""
            if email.isEmpty {
                if tty {
                    email = prompt("Email: ")
                } else {
                    throw OliveMailError.missingEmail
                }
            }
            if email.isEmpty { throw OliveMailError.emptyEmail }

            var imap = self.imap ?? ""
            if imap.isEmpty {
                if tty {
                    imap = prompt("IMAP server (e.g. imaps://imap.example.com:993): ")
                } else {
                    throw OliveMailError.missingImap
                }
            }
            if imap.isEmpty { throw OliveMailError.emptyImap }

            let paths = try Paths.resolve()
            let password: String
            if tty {
                let err = FileHandle.standardError
                err.write(Data("Mailbox: \(email)\n".utf8))
                err.write(Data("IMAP:    \(imap)\n".utf8))
                err.write(Data("Secret:  \(paths.passFile(email: email))\n".utf8))
                let first = try readPassword(prompt: "App password: ")
                let second = try readPassword(prompt: "Again: ")
                if first != second { throw OliveMailError.passwordsMismatch }
                password = first
            } else {
                password = readStdinPassword()
            }
            if password.isEmpty { throw OliveMailError.emptyPassword }

            try AccountStore.write(
                paths: paths,
                email: email,
                imap: imap,
                password: password
            )
        }
    }

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List accounts."
        )

        @Flag(help: "JSON output.")
        var json = false

        mutating func run() async throws {}
    }
}

private func prompt(_ message: String) -> String {
    FileHandle.standardError.write(Data(message.utf8))
    return (readLine() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
}

private func readStdinPassword() -> String {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    var text = String(data: data, encoding: .utf8) ?? ""
    while text.hasSuffix("\n") || text.hasSuffix("\r") {
        text.removeLast()
    }
    return text
}

private func readPassword(prompt: String) throws -> String {
    FileHandle.standardError.write(Data(prompt.utf8))
    var original = termios()
    guard tcgetattr(FileHandle.standardInput.fileDescriptor, &original) == 0 else {
        return (readLine() ?? "")
    }
    var silent = original
    silent.c_lflag &= ~tcflag_t(ECHO)
    _ = tcsetattr(FileHandle.standardInput.fileDescriptor, TCSANOW, &silent)
    defer {
        _ = tcsetattr(FileHandle.standardInput.fileDescriptor, TCSANOW, &original)
        FileHandle.standardError.write(Data("\n".utf8))
    }
    return readLine() ?? ""
}
