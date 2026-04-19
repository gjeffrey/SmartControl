import Foundation

struct CommandResult: Hashable {
    let executable: String
    let arguments: [String]
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

enum CommandRunnerError: Error {
    case invalidExecutable(String)
}

struct CommandRunner {
    enum PrivilegeMode {
        case standard
        case administratorPrompt(prompt: String)
    }

    func run(
        executable: String,
        arguments: [String],
        privilegeMode: PrivilegeMode = .standard
    ) async throws -> CommandResult {
        switch privilegeMode {
        case .standard:
            return try await launch(executable: executable, arguments: arguments)
        case let .administratorPrompt(prompt):
            let shellCommand = ([executable] + arguments).map(shellEscape).joined(separator: " ")
            return try await runShell(shellCommand, privilegeMode: .administratorPrompt(prompt: prompt))
        }
    }

    func runShell(
        _ shellCommand: String,
        privilegeMode: PrivilegeMode = .standard
    ) async throws -> CommandResult {
        switch privilegeMode {
        case .standard:
            return try await launch(executable: "/bin/zsh", arguments: ["-lc", shellCommand])
        case let .administratorPrompt(prompt):
            let escapedPrompt = appleScriptEscape(prompt)
            let script = "do shell script \"\(appleScriptEscape(shellCommand))\" with administrator privileges with prompt \"\(escapedPrompt)\""
            return try await launch(executable: "/usr/bin/osascript", arguments: ["-e", script])
        }
    }

    private func launch(executable: String, arguments: [String]) async throws -> CommandResult {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw CommandRunnerError.invalidExecutable(executable)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            process.terminationHandler = { process in
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(
                    returning: CommandResult(
                        executable: executable,
                        arguments: arguments,
                        stdout: String(decoding: stdoutData, as: UTF8.self),
                        stderr: String(decoding: stderrData, as: UTF8.self),
                        exitCode: process.terminationStatus
                    )
                )
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func shellEscape(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func appleScriptEscape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
