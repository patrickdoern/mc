import Foundation

final class Bsdtar {
    private static let executable = "/usr/bin/bsdtar"
    private static let errorLimit = 4096

    let output: FileHandle?
    private let process = Process()
    private let errorsDone = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var errors = Data()
    private var asksForPassphrase = false

    init(_ arguments: [String], capturesOutput: Bool) throws {
        process.executableURL = URL(fileURLWithPath: Self.executable)
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(["LC_ALL": "C"]) { $1 }
        process.standardInput = FileHandle.nullDevice
        let pipe = capturesOutput ? Pipe() : nil
        process.standardOutput = pipe ?? FileHandle.nullDevice
        output = pipe?.fileHandleForReading
        let errorPipe = Pipe()
        process.standardError = errorPipe
        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self else { return }
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                errorsDone.signal()
                return
            }
            received(data)
        }
        try process.run()
    }

    var isRunning: Bool { process.isRunning }

    func terminate() {
        if process.isRunning { process.terminate() }
    }

    func failure() -> String? {
        process.waitUntilExit()
        _ = errorsDone.wait(timeout: .now() + 1)
        return lock.withLock {
            if asksForPassphrase { return localized("verschlüsselte Archive werden nicht unterstützt") }
            guard process.terminationReason != .exit || process.terminationStatus != 0 else { return nil }
            return String(decoding: errors, as: UTF8.self).split(separator: "\n").first.map(String.init) ?? ""
        }
    }

    private func received(_ data: Data) {
        let encrypted: Bool = lock.withLock {
            if errors.count < Self.errorLimit { errors.append(data) }
            guard !asksForPassphrase, String(decoding: errors, as: UTF8.self).lowercased().contains("passphrase") else { return false }
            asksForPassphrase = true
            return true
        }
        if encrypted { terminate() }
    }
}
