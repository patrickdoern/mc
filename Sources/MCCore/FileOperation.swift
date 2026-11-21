import Foundation

public final class FileOperation {
    private static let newerTolerance: TimeInterval = 2
    private static let maxLinkDepth = 40

    private let handlers: OperationHandlers
    private let options: TransferOptions
    private let cancelLock = NSLock()
    private var cancelled = false
    private var progress = OperationProgress()
    private var lastReport = Date.distantPast
    private var rule: OverwriteRule
    private var skipAllFailures = false
    private var skipped = 0

    public init(handlers: OperationHandlers, options: TransferOptions = TransferOptions()) {
        self.handlers = handlers
        self.options = options
        rule = options.overwriteRule
    }

    public func cancel() {
        cancelLock.lock()
        cancelled = true
        cancelLock.unlock()
    }

    public func copy(_ transfers: [Transfer], from source: FileSystem, to destination: FileSystem) throws {
        try transaction([source, destination]) {
            try scan(transfers.map(\.source), on: source)
            for transfer in transfers {
                try attempt(transfer.source) {
                    try copyItem(transfer.source, to: transfer.destination, from: source, into: destination, entry: try source.stat(transfer.source))
                }
            }
            report(force: true)
        }
    }

    public func move(_ transfers: [Transfer], from source: FileSystem, to destination: FileSystem) throws {
        try transaction([source, destination]) {
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
    }

    public func delete(_ paths: [String], on fileSystem: FileSystem, trash: Bool) throws {
        try transaction([fileSystem]) {
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
    }

    private func transaction(_ systems: [FileSystem], _ body: () throws -> Void) throws {
        var unique: [FileSystem] = []
        for system in systems where !unique.contains(where: { Self.isSameFileSystem($0, system) }) {
            unique.append(system)
        }
        unique.forEach { $0.beginTransaction() }
        do {
            try body()
        } catch {
            unique.forEach { $0.rollbackTransaction() }
            throw error
        }
        var pending = Array(unique.reversed())
        while let system = pending.first {
            if system.hasPendingChanges {
                progress.currentPath = PosixPath.name(system.displayName)
                report(force: true)
            }
            do {
                try system.commitTransaction()
            } catch {
                pending.forEach { $0.rollbackTransaction() }
                throw error
            }
            pending.removeFirst()
        }
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

    private func scanItem(_ path: String, on fileSystem: FileSystem, links: Int = 0, ancestors: [String] = []) throws {
        var links = links
        var ancestors = ancestors
        try checkCancelled()
        guard var entry = try? fileSystem.stat(path) else { return }
        if entry.isSymlink && options.followSymlinks {
            guard links < Self.maxLinkDepth, let target = try? followed(entry, at: path, on: fileSystem) else { return }
            entry = target
            links += 1
        }
        if entry.isDirectory && !entry.isSymlink {
            if options.followSymlinks, let canonical = fileSystem.canonicalPath(path) {
                if ancestors.contains(canonical) { return }
                ancestors.append(canonical)
            }
            progress.currentPath = path
            report()
            for child in (try? fileSystem.list(path)) ?? [] {
                try scanItem(PosixPath.join(path, child.name), on: fileSystem, links: links, ancestors: ancestors)
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
            let skippedBefore = skipped
            for child in try fileSystem.list(source) {
                let childSource = PosixPath.join(source, child.name)
                try attempt(childSource) { try moveItem(childSource, to: PosixPath.join(destination, child.name), on: fileSystem) }
            }
            if skipped == skippedBefore { try fileSystem.removeDirectory(source) }
            return
        }
        guard try shouldOverwrite(destination, source: entry, existing: existing) else { return }
        try removeTree(destination, on: fileSystem, entry: existing)
        try fileSystem.rename(source, destination)
    }

    private func shouldOverwrite(_ path: String, source: FileEntry, existing: FileEntry) throws -> Bool {
        switch rule {
        case .overwrite:
            return true
        case .skip:
            skipped += 1
            return false
        case .ifSizeDiffers:
            return replaceIf(source.size != existing.size)
        case .ifNewer:
            if let sourceTime = source.modified, let existingTime = existing.modified {
                return replaceIf(sourceTime.timeIntervalSince(existingTime) > Self.newerTolerance)
            }
        case .ask:
            break
        }
        switch handlers.resolveConflict(ConflictInfo(path: path, source: source, existing: existing)) {
        case .overwrite: return true
        case .overwriteAll: rule = .overwrite; return true
        case .overwriteThenRule(let next): rule = next; return true
        case .skip: skipped += 1; return false
        case .skipAll: rule = .skip; skipped += 1; return false
        case .skipThenRule(let next): rule = next; skipped += 1; return false
        case .cancel: throw OperationAborted()
        }
    }

    private func replaceIf(_ condition: Bool) -> Bool {
        if !condition { skipped += 1 }
        return condition
    }

    private func followed(_ entry: FileEntry, at path: String, on fileSystem: FileSystem) throws -> FileEntry {
        let target = try fileSystem.statFollowingLinks(path)
        return FileEntry(name: entry.name, isDirectory: target.isDirectory, size: target.size, modified: target.modified, permissions: target.permissions, accessed: target.accessed, changed: target.changed, created: target.created)
    }

    private func copyItem(_ source: String, to destination: String, from sourceSystem: FileSystem, into destinationSystem: FileSystem, entry: FileEntry, links: Int = 0, ancestors: [String] = []) throws {
        try checkCancelled()
        var entry = entry
        var links = links
        if entry.isSymlink && options.followSymlinks {
            guard links < Self.maxLinkDepth else { throw FileError(localized("Zu viele verschachtelte Symlinks: %@", source as NSString)) }
            entry = try followed(entry, at: source, on: sourceSystem)
            links += 1
        }
        if Self.isSameFileSystem(sourceSystem, destinationSystem) {
            if source == destination { throw FileError(localized("Quelle und Ziel sind identisch: %@", source as NSString)) }
            if entry.isDirectory, destination.hasPrefix(source + "/") { throw FileError(localized("Ein Ordner kann nicht in sich selbst kopiert werden: %@", source as NSString)) }
        }
        progress.currentPath = source
        report()
        let existing = try? destinationSystem.stat(destination)
        if entry.isDirectory && !entry.isSymlink {
            try copyDirectory(source, to: destination, from: sourceSystem, into: destinationSystem, entry: entry, existing: existing, links: links, ancestors: ancestors)
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

    private func copyDirectory(_ source: String, to destination: String, from sourceSystem: FileSystem, into destinationSystem: FileSystem, entry: FileEntry, existing: FileEntry?, links: Int, ancestors: [String]) throws {
        var ancestors = ancestors
        if options.followSymlinks, let canonical = sourceSystem.canonicalPath(source) {
            guard !ancestors.contains(canonical) else { throw FileError(localized("Zu viele verschachtelte Symlinks: %@", source as NSString)) }
            ancestors.append(canonical)
        }
        if let existing {
            guard existing.isDirectory else { throw FileError(localized("Ziel ist kein Ordner: %@", destination as NSString)) }
        } else {
            try destinationSystem.makeDirectory(destination)
        }
        for child in try sourceSystem.list(source) {
            let childSource = PosixPath.join(source, child.name)
            try attempt(childSource) {
                try copyItem(childSource, to: PosixPath.join(destination, child.name), from: sourceSystem, into: destinationSystem, entry: child, links: links, ancestors: ancestors)
            }
        }
        if options.preserveAttributes, let modified = entry.modified { try? destinationSystem.setModified(destination, modified) }
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
        if options.preserveAttributes, let modified = entry.modified { try? destinationSystem.setModified(destination, modified) }
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
        let flags = options.preserveAttributes ? COPYFILE_ALL | (options.followSymlinks ? 0 : COPYFILE_CLONE) : COPYFILE_DATA
        let result = copyfile(source, destination, state, copyfile_flags_t(flags))
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
