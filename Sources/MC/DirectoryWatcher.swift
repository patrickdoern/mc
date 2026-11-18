import CoreServices
import Foundation

final class DirectoryWatcher {
    private let path: String
    private let onChange: () -> Void
    private var stream: FSEventStreamRef?

    init(path: String, onChange: @escaping () -> Void) {
        self.path = realpath(path, nil).map { resolved in
            defer { free(resolved) }
            return String(cString: resolved)
        } ?? path
        self.onChange = onChange
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<DirectoryWatcher>.fromOpaque(info).takeUnretainedValue()
            let changed = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as? [String] ?? []
            if changed.contains(where: { watcher.isWatchedDirectory($0) }) { watcher.onChange() }
        }
        guard let created = FSEventStreamCreate(nil, callback, &context, [self.path] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.4, FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes)) else { return }
        stream = created
        FSEventStreamSetDispatchQueue(created, .main)
        FSEventStreamStart(created)
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }

    private func isWatchedDirectory(_ eventPath: String) -> Bool {
        let trimmed = eventPath.count > 1 && eventPath.hasSuffix("/") ? String(eventPath.dropLast()) : eventPath
        return trimmed == path
    }
}
