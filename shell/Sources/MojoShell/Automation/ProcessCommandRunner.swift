import Foundation

enum ProcessCommandRunner {
    static func run(_ executable: String, _ arguments: [String], _ stdin: String?) async throws -> String {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        let stdinPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr

        if stdin != nil {
            process.standardInput = stdinPipe
        }

        try process.run()

        if let stdin {
            stdinPipe.fileHandleForWriting.write(Data(stdin.utf8))
            try? stdinPipe.fileHandleForWriting.close()
        }

        process.waitUntilExit()

        let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()

        if process.terminationStatus != 0 {
            let stderrText = String(decoding: stderrData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            let message = stderrText.isEmpty ? "Command failed with status \(process.terminationStatus)." : stderrText
            throw NativeToolError.commandFailed(message)
        }

        return String(decoding: stdoutData, as: UTF8.self)
    }
}
