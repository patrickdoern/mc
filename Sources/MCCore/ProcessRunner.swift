import Foundation

public struct ProcessResult {
    public let status: Int32
    public let output: Data
    public let errors: Data

    public var succeeded: Bool { status == 0 }
    public var outputText: String { String(decoding: output, as: UTF8.self) }
    public var errorText: String { String(decoding: errors, as: UTF8.self) }
}

public enum ProcessRunner {
    public static func run(_ executable: String, _ arguments: [String], directory: String? = nil, mergingErrors: Bool = false) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let directory { process.currentDirectoryURL = URL(fileURLWithPath: directory) }
        process.standardInput = FileHandle.nullDevice
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = mergingErrors ? output : errors
        try process.run()
        var errorData = Data()
        let errorsRead = DispatchGroup()
        if !mergingErrors {
            errorsRead.enter()
            DispatchQueue.global(qos: .utility).async {
                errorData = errors.fileHandleForReading.readDataToEndOfFile()
                errorsRead.leave()
            }
        }
        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        errorsRead.wait()
        process.waitUntilExit()
        return ProcessResult(status: process.terminationStatus, output: outputData, errors: errorData)
    }
}
