import Foundation

public final class FileOperation {
    private let handlers: OperationHandlers
    private let cancelLock = NSLock()
    private var cancelled = false
    private var progress = OperationProgress()
    private var lastReport = Date.distantPast
    private var overwriteAll = false
    private var skipAllConflicts = false
    private var skipAllFailures = false
    private var skipped = 0

    public init(handlers: OperationHandlers) {
        self.handlers = handlers
    }

    public func cancel() {
        cancelLock.lock()
        cancelled = true
        cancelLock.unlock()
    }

    public func copy(_ transfers: [Transfer], from source: FileSystem, to destination: FileSystem) throws {
        try scan(transfers.map(\.source), on: source)
        for transfer in transfers {
            try attempt(transfer.source) {
                try copyItem(transfer.source, to: transfer.destination, from: source, into: destination, entry: try source.stat(transfer.source))
            }
        }
        report(force: true)
    }

    public func move(_ transfers: [Transfer], from source: FileSystem, to destination: FileSystem) throws {
        if Self.isSameFileSystem(source, destination) {
            progress.filesTotal = transfers.count
            for transfer in transfers {
                try attempt(transfer.source) { try moveItem(transfer.source, to: transfer.destination, on: source) }
                progress.filesDone += 1
            }
        } else {
            try scan(transfers.map(\.source), on: source)
            for transfer in transfers {
                let skippedBefore = skipped
                try attempt(transfer.source) {
                    let entry = try source.stat(transfer.source)
                    try copyItem(transfer.source, to: transfer.destination, from: source, into: destination, entry: entry)
                    if skipped == skippedBefore { try removeTree(transfer.source, on: source, entry: entry) }
                }
            }
        }
        report(force: true)
    }

    public func delete(_ paths: [String], on fileSystem: FileSystem, trash: Bool) throws {
        if trash, let local = fileSystem as? LocalFileSystem {
            progress.filesTotal = paths.count
            for path in paths {
                try attempt(path) { try local.trash(path) }
                progress.filesDone += 1
                progress.currentPath = path
                report(force: true)
            }
            return
        }
        try scan(paths, on: fileSystem)
        progress.bytesTotal = 0
        for path in paths {
            try attempt(path) { try removeTree(path, on: fileSystem, entry: try fileSystem.stat(path)) }
        }
        report(force: true)
    }

    private static func isSameFileSystem(_ first: FileSystem, _ second: FileSystem) -> Bool {
        first === second || first.identity == second.identity
    }

    private func checkCancelled() throws {
        cancelLock.lock()
        defer { cancelLock.unlock() }
        if cancelled { throw OperationAborted() }
    }

    private func report(force: Bool = false) {
        let now = Date()
        guard force || now.timeIntervalSince(lastReport) >= 0.05 else { return }
        lastReport = now
        handlers.progress(progress)
    }

    private func attempt(_ path: String, _ body: () throws -> Void) throws {
        try checkCancelled()
        do {
            try body()
        } catch let error as OperationAborted {
            throw error
        } catch {
            skipped += 1
            if skipAllFailures { return }
            switch handlers.resolveFailure(path, error) {
            case .skip: return
            case .skipAll: skipAllFailures = true
            case .abort: throw OperationAborted()
            }
        }
    }

    private func scan(_ paths: [String], on fileSystem: FileSystem) throws {
        for path in paths {
            try scanItem(path, on: fileSystem)
        }
        report(force: true)
    }

    private func scanItem(_ path: String, on fileSystem: FileSystem) throws {
        try checkCancelled()
        guard let entry = try? fileSystem.stat(path) else { return }
        if entry.isDirectory && !entry.isSymlink {
            progress.currentPath = path
            report()
            for child in (try? fileSystem.list(path)) ?? [] {
                try scanItem(PosixPath.join(path, child.name), on: fileSystem)
            }
        } else {
            progress.filesTotal += 1
            progress.bytesTotal += entry.isSymlink ? 0 : entry.size
        }
    }

    private func removeTree(_ path: String, on fileSystem: FileSystem, entry: FileEntry) throws {
        try checkCancelled()
        progress.currentPath = path
        if entry.isDirectory && !entry.isSymlink {
            for child in try fileSystem.list(path) {
                let childPath = PosixPath.join(path, child.name)
                try attempt(childPath) { try removeTree(childPath, on: fileSystem, entry: child) }
            }
            try fileSystem.removeDirectory(path)
        } else {
            try fileSystem.removeFile(path)
            progress.filesDone += 1
        }
        report()
    }

    private func moveItem(_ source: String, to destination: String, on fileSystem: FileSystem) throws {
        try checkCancelled()
        progress.currentPath = source
        report()
        let entry = try fileSystem.stat(source)
        guard let existing = try? fileSystem.stat(destination) else {
            do {
                try fileSystem.rename(source, destination)
            } catch {
                try copyItem(source, to: destination, from: fileSystem, into: fileSystem, entry: entry)
                try removeTree(source, on: fileSystem, entry: entry)
            }
            return
        }
        if existing.isDirectory && !existing.isSymlink && entry.isDirectory && !entry.isSymlink {
            for child in try fileSystem.list(source) {
                let childSource = PosixPath.join(source, child.name)
                try attempt(childSource) { try moveItem(childSource, to: PosixPath.join(destination, child.name), on: fileSystem) }
            }
            try fileSystem.removeDirectory(source)
            return
        }
        guard try shouldOverwrite(destination, source: entry, existing: existing) else { return }
        try removeTree(destination, on: fileSystem, entry: existing)
        try fileSystem.rename(source, destination)
    }

    private func shouldOverwrite(_ path: String, source: FileEntry, existing: FileEntry) throws -> Bool {
        if overwriteAll { return true }
        if skipAllConflicts { skipped += 1; return false }
        switch handlers.resolveConflict(ConflictInfo(path: path, source: source, existing: existing)) {
        case .overwrite: return true
        case .overwriteAll: overwriteAll = true; return true
        case .skip: skipped += 1; return false
        case .skipAll: skipAllConflicts = true; skipped += 1; return false
        case .cancel: throw OperationAborted()
        }
    }

    private func copyItem(_ source: String, to destination: String, from sourceSystem: FileSystem, into destinationSystem: FileSystem, entry: FileEntry) throws {
        try checkCancelled()
        if Self.isSameFileSystem(sourceSystem, destinationSystem) {
            if source == destination { throw FileError(localized("Quelle und Ziel sind identisch: %@", source as NSString)) }
            if entry.isDirectory, destination.hasPrefix(source + "/") { throw FileError(localized("Ein Ordner kann nicht in sich selbst kopiert werden: %@", source as NSString)) }
        }
        progress.currentPath = source
        report()
        let existing = try? destinationSystem.stat(destination)
        if entry.isDirectory && !entry.isSymlink {
            try copyDirectory(source, to: destination, from: sourceSystem, into: destinationSystem, entry: entry, existing: existing)
            return
        }
        if let existing {
            if existing.isDirectory && !existing.isSymlink { throw FileError(localized("Ziel ist ein Ordner: %@", destination as NSString)) }
            guard try shouldOverwrite(destination, source: entry, existing: existing) else { return }
            try destinationSystem.removeFile(destination)
        }
        if entry.isSymlink {
            try destinationSystem.makeSymlink(destination, target: try sourceSystem.readLink(source))
            progress.filesDone += 1
        } else {
            try copyFile(source, to: destination, from: sourceSystem, into: destinationSystem, entry: entry)
        }
        report()
    }

    private func copyDirectory(_ source: String, to destination: String, from sourceSystem: FileSystem, into destinationSystem: FileSystem, entry: FileEntry, existing: FileEntry?) throws {
        if let existing {
            guard existing.isDirectory else { throw FileError(localized("Ziel ist kein Ordner: %@", destination as NSString)) }
        } else {
            try destinationSystem.makeDirectory(destination)
        }
        for child in try sourceSystem.list(source) {
            let childSource = PosixPath.join(source, child.name)
            try attempt(childSource) {
                try copyItem(childSource, to: PosixPath.join(destination, child.name), from: sourceSystem, into: destinationSystem, entry: child)
            }
        }
        if let modified = entry.modified { try? destinationSystem.setModified(destination, modified) }
    }

    private func copyFile(_ source: String, to destination: String, from sourceSystem: FileSystem, into destinationSystem: FileSystem, entry: FileEntry) throws {
        let baseBytes = progress.bytesDone
        do {
            if sourceSystem is LocalFileSystem, destinationSystem is LocalFileSystem {
                try copyLocalFile(source, to: destination, baseBytes: baseBytes)
            } else {
                try streamFile(source, to: destination, from: sourceSystem, into: destinationSystem, entry: entry)
            }
        } catch {
            try? destinationSystem.removeFile(destination)
            progress.bytesDone = baseBytes
            throw error
        }
        progress.bytesDone = baseBytes + entry.size
        progress.filesDone += 1
    }

    private func streamFile(_ source: String, to destination: String, from sourceSystem: FileSystem, into destinationSystem: FileSystem, entry: FileEntry) throws {
        let reader = try sourceSystem.openReader(source)
        defer { reader.close() }
        let writer = try destinationSystem.openWriter(destination, permissions: entry.permissions)
        var buffer = [UInt8](repeating: 0, count: 256 * 1024)
        do {
            while true {
                try checkCancelled()
                let count = try buffer.withUnsafeMutableBytes { try reader.read(into: $0) }
                if count == 0 { break }
                try buffer.withUnsafeBytes { try writer.write(UnsafeRawBufferPointer(rebasing: $0[0..<count])) }
                progress.bytesDone += Int64(count)
                report()
            }
        } catch {
            writer.abort()
            throw error
        }
        try writer.finish()
        if let modified = entry.modified { try? destinationSystem.setModified(destination, modified) }
    }

    private func copyLocalFile(_ source: String, to destination: String, baseBytes: Int64) throws {
        let state = copyfile_state_alloc()
        defer { copyfile_state_free(state) }
        let context = Unmanaged.passRetained(LocalCopyContext { [self] copied in
            progress.bytesDone = baseBytes + copied
            report()
            cancelLock.lock()
            defer { cancelLock.unlock() }
            return !cancelled
        })
        defer { context.release() }
        let callback: copyfile_callback_t = { what, stage, state, _, _, context in
            guard what == COPYFILE_COPY_DATA, stage == COPYFILE_PROGRESS, let context, let state else { return COPYFILE_CONTINUE }
            var copied: off_t = 0
            copyfile_state_get(state, UInt32(COPYFILE_STATE_COPIED), &copied)
            let keepGoing = Unmanaged<LocalCopyContext>.fromOpaque(context).takeUnretainedValue().onProgress(Int64(copied))
            return keepGoing ? COPYFILE_CONTINUE : COPYFILE_QUIT
        }
        copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CB), unsafeBitCast(callback, to: UnsafeRawPointer.self))
        copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CTX), context.toOpaque())
        let result = copyfile(source, destination, state, copyfile_flags_t(COPYFILE_ALL | COPYFILE_CLONE))
        try checkCancelled()
        guard result == 0 else { throw FileError(path: source, errno: errno) }
    }
}

private final class LocalCopyContext {
    let onProgress: (Int64) -> Bool

    init(onProgress: @escaping (Int64) -> Bool) {
        self.onProgress = onProgress
    }
}
