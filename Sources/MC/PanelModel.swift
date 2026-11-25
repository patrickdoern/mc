import Foundation
import MCCore

enum SortKey: Int {
    case name, fileExtension, size, date, accessTime, changeTime, creationTime

    var entryTime: EntryTime {
        switch self {
        case .name, .fileExtension, .size, .date: .modified
        case .accessTime: .accessed
        case .changeTime: .changed
        case .creationTime: .created
        }
    }
}

enum ListFormat: Int, CaseIterable {
    case full, sizeOnly, permissions, namesOnly, brief

    var title: String {
        switch self {
        case .full: return localized("Name, Größe, Datum")
        case .sizeOnly: return localized("Name, Größe")
        case .permissions: return localized("Name, Rechte, Größe")
        case .namesOnly: return localized("Nur Name")
        case .brief: return localized("Kurz (mehrspaltig)")
        }
    }
}

private struct Place: Equatable {
    let fileSystem: FileSystem
    let path: String

    var key: String { fileSystem.identity + "\n" + path }

    var text: String { fileSystem is LocalFileSystem ? path : fileSystem.displayName + ":" + path }

    static func == (lhs: Place, rhs: Place) -> Bool {
        lhs.fileSystem.identity == rhs.fileSystem.identity && lhs.path == rhs.path
    }
}

final class PanelModel {
    static let parentName = ".."

    private(set) var fileSystem: FileSystem
    private(set) var path: String
    private(set) var rows: [FileEntry] = []
    private(set) var marked: Set<String> = []
    private(set) var sortKey: SortKey
    private(set) var ascending: Bool
    private(set) var showHidden: Bool
    private(set) var dirsFirst: Bool
    private(set) var caseSensitive: Bool
    private(set) var format: ListFormat
    private(set) var filter = ""
    private(set) var isLoading = false
    private(set) var searchText: String?
    private(set) var directorySizes: [String: Int64] = [:]
    var cursor = 0
    var onChange: (() -> Void)?
    var onFailure: ((Error) -> Void)?
    var onNavigate: (() -> Void)?

    private var entries: [FileEntry] = []
    private var generation = 0
    private var watcher: DirectoryWatcher?
    private var watchedPath: String?
    private var refreshPending = false
    private var history = NavigationHistory<Place>()
    private var leftNames: [String: String] = [:]

    init(fileSystem: FileSystem, path: String, sortKey: SortKey, ascending: Bool, showHidden: Bool, dirsFirst: Bool, caseSensitive: Bool, format: ListFormat) {
        self.fileSystem = fileSystem
        self.path = path
        self.sortKey = sortKey
        self.ascending = ascending
        self.showHidden = showHidden
        self.dirsFirst = dirsFirst
        self.caseSensitive = caseSensitive
        self.format = format
    }

    var isLocal: Bool { fileSystem is LocalFileSystem }

    var title: String {
        let location = isLocal ? path : fileSystem.displayName + ":" + path
        return filter.isEmpty ? location : location + " [\(filter)]"
    }

    var hasParentRow: Bool { path != "/" || fileSystem.exitLocation != nil }

    var currentEntry: FileEntry? { rows.indices.contains(cursor) ? rows[cursor] : nil }

    var selectedNames: [String] {
        if !marked.isEmpty { return rows.map(\.name).filter(marked.contains) }
        guard let entry = currentEntry, !isParentRow(cursor) else { return [] }
        return [entry.name]
    }

    var markedBytes: Int64 { rows.filter { marked.contains($0.name) && !$0.isDirectory }.reduce(0) { $0 + $1.size } }

    func isParentRow(_ index: Int) -> Bool { hasParentRow && index == 0 }

    var canGoBack: Bool { history.canGoBack }

    var canGoForward: Bool { history.canGoForward }

    var historyItems: [(text: String, isCurrent: Bool)] {
        history.elements.indices.reversed().map { (text: history.elements[$0].text, isCurrent: $0 == history.position) }
    }

    var localHistoryPaths: [String] {
        history.elements.filter { $0.fileSystem is LocalFileSystem }.map(\.path)
    }

    func restoreHistory(localPaths: [String]) {
        history = NavigationHistory(elements: localPaths.map { Place(fileSystem: LocalFileSystem.shared, path: $0) })
    }

    func goBack() {
        guard history.canGoBack else { return }
        step(to: history.position - 1)
    }

    func goForward() {
        guard history.canGoForward else { return }
        step(to: history.position + 1)
    }

    func goToHistory(item index: Int) {
        let target = history.elements.count - 1 - index
        guard history.elements.indices.contains(target), target != history.position else { return }
        step(to: target)
    }

    private func step(to index: Int) {
        let place = history.elements[index]
        load(to: place.path, on: place.fileSystem, selecting: leftNames[place.key], quiet: false, historyIndex: index)
    }

    func navigate(to newPath: String, on newSystem: FileSystem? = nil, selecting name: String? = nil, quiet: Bool = false) {
        load(to: newPath, on: newSystem, selecting: name, quiet: quiet, historyIndex: nil)
    }

    private func load(to newPath: String, on newSystem: FileSystem?, selecting name: String?, quiet: Bool, historyIndex: Int?) {
        generation += 1
        let token = generation
        let system = newSystem ?? fileSystem
        let keepMarks = newPath == path && newSystem == nil
        isLoading = true
        if !quiet { onChange?() }
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try system.list(newPath) }
            DispatchQueue.main.async { [self] in
                guard token == generation else { return }
                isLoading = false
                switch result {
                case .success(let listing):
                    let keptMarks = keepMarks ? marked.intersection(listing.map(\.name)) : []
                    let previous = Place(fileSystem: fileSystem, path: path)
                    let arrived = Place(fileSystem: system, path: newPath)
                    if previous != arrived, !isParentRow(cursor), let current = currentEntry {
                        leftNames[previous.key] = current.name
                    }
                    fileSystem = system
                    path = newPath
                    entries = listing
                    marked = keptMarks
                    if !keepMarks { directorySizes = [:] }
                    if let historyIndex {
                        history.jump(to: historyIndex)
                        cursor = 0
                    } else if !quiet {
                        history.record(arrived)
                        if leftNames.count > history.limit {
                            let keys = Set(history.elements.map(\.key))
                            leftNames = leftNames.filter { keys.contains($0.key) }
                        }
                    }
                    rebuild(selecting: name)
                    watchDirectory()
                case .failure(let error):
                    if system.isDisconnected {
                        if !quiet { onFailure?(error) }
                        navigate(to: NSHomeDirectory(), on: LocalFileSystem.shared)
                        return
                    }
                    if let historyIndex {
                        history.remove(at: historyIndex)
                    } else if newSystem == nil, newPath == path, path != "/" {
                        navigate(to: PosixPath.parent(path), selecting: PosixPath.name(path))
                        return
                    }
                    if !quiet { onFailure?(error) }
                }
                onChange?()
                if !quiet { onNavigate?() }
                if refreshPending {
                    refreshPending = false
                    refreshQuietly()
                }
            }
        }
    }

    private func watchDirectory() {
        guard isLocal else {
            watcher = nil
            watchedPath = nil
            return
        }
        guard watchedPath != path else { return }
        watchedPath = path
        watcher = DirectoryWatcher(path: path) { [weak self] in self?.refreshQuietly() }
    }

    private func refreshQuietly() {
        guard !isLoading else {
            refreshPending = true
            return
        }
        navigate(to: path, selecting: currentEntry?.name, quiet: true)
    }

    func reload(selecting name: String? = nil) {
        navigate(to: path, selecting: name ?? currentEntry?.name)
    }

    func goUp() {
        guard hasParentRow else { return }
        if path == "/", let exit = fileSystem.exitLocation {
            navigate(to: exit.path, on: exit.system, selecting: exit.selecting)
            return
        }
        navigate(to: PosixPath.parent(path), selecting: PosixPath.name(path))
    }

    func enterCursor() -> FileEntry? {
        guard let entry = currentEntry else { return nil }
        if isParentRow(cursor) {
            goUp()
        } else if entry.isDirectory {
            navigate(to: PosixPath.join(path, entry.name))
        } else {
            return entry
        }
        return nil
    }

    func fullPath(of name: String) -> String { PosixPath.join(path, name) }

    func moveCursor(by delta: Int) {
        cursor = min(max(cursor + delta, 0), max(rows.count - 1, 0))
        onChange?()
    }

    func setCursor(_ index: Int) {
        cursor = min(max(index, 0), max(rows.count - 1, 0))
        onChange?()
    }

    func toggleMarkAndAdvance(by delta: Int = 1) {
        guard let entry = currentEntry, !isParentRow(cursor) else { return moveCursor(by: delta) }
        if !marked.insert(entry.name).inserted { marked.remove(entry.name) }
        moveCursor(by: delta)
    }

    func mark(matching pattern: String, select: Bool) {
        for (index, entry) in rows.enumerated() where !isParentRow(index) && fnmatch(pattern, entry.name, FNM_CASEFOLD) == 0 {
            if select { marked.insert(entry.name) } else { marked.remove(entry.name) }
        }
        onChange?()
    }

    func markAll() {
        marked = Set(rows.indices.filter { !isParentRow($0) }.map { rows[$0].name })
        onChange?()
    }

    func invertMarks() {
        marked = Set(rows.indices.filter { !isParentRow($0) }.map { rows[$0].name }).subtracting(marked)
        onChange?()
    }

    func clearMarks() {
        marked = []
        onChange?()
    }

    func calculateDirectorySizes() {
        let candidates = marked.isEmpty ? [currentEntry].compactMap { $0 } : rows.filter { marked.contains($0.name) }
        let names = candidates.filter { $0.isDirectory && $0.name != Self.parentName }.map(\.name)
        let system = fileSystem
        let base = path
        let token = generation
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            for name in names {
                let size = DirectorySize.total(of: PosixPath.join(base, name), on: system) { self?.generation != token }
                DispatchQueue.main.async {
                    guard let self, token == self.generation else { return }
                    self.directorySizes[name] = size
                    self.onChange?()
                }
            }
        }
    }

    @discardableResult
    func markDifferences(against other: PanelModel) -> Int {
        let counterparts = Dictionary(other.rows.filter { $0.name != Self.parentName }.map { ($0.name, $0) }) { first, _ in first }
        marked = Set(rows.filter { entry in
            guard entry.name != Self.parentName else { return false }
            guard let counterpart = counterparts[entry.name] else { return true }
            guard !entry.isDirectory else { return false }
            return entry.size != counterpart.size || (entry.modified ?? .distantPast) > (counterpart.modified ?? .distantPast).addingTimeInterval(1)
        }.map(\.name))
        onChange?()
        return marked.count
    }

    func sort(by key: SortKey) {
        if sortKey == key { ascending.toggle() } else { sortKey = key; ascending = true }
        rebuild(selecting: currentEntry?.name)
        onChange?()
    }

    func applySortOptions(key: SortKey, ascending: Bool, dirsFirst: Bool, caseSensitive: Bool) {
        sortKey = key
        self.ascending = ascending
        self.dirsFirst = dirsFirst
        self.caseSensitive = caseSensitive
        rebuild(selecting: currentEntry?.name)
        onChange?()
    }

    func setFormat(_ newFormat: ListFormat) {
        format = newFormat
        onChange?()
    }

    func setFilter(_ pattern: String) {
        filter = pattern
        rebuild(selecting: currentEntry?.name)
        onChange?()
    }

    func toggleHidden() {
        showHidden.toggle()
        rebuild(selecting: currentEntry?.name)
        onChange?()
    }

    func beginSearch() {
        searchText = ""
        onChange?()
    }

    func endSearch() {
        searchText = nil
        onChange?()
    }

    func updateSearch(_ text: String) {
        searchText = text
        if let index = rows.indices.first(where: { !isParentRow($0) && rows[$0].name.range(of: text, options: [.anchored, .caseInsensitive]) != nil }) {
            cursor = index
        }
        onChange?()
    }

    private func rebuild(selecting name: String?) {
        let patterns = filter.split(separator: " ").map(String.init)
        let visible = entries.filter { entry in
            (showHidden || !entry.isHidden) && (entry.isDirectory || patterns.isEmpty || patterns.contains { fnmatch($0, entry.name, FNM_CASEFOLD) == 0 })
        }
        rows = visible.sorted(by: areInOrder)
        if hasParentRow { rows.insert(FileEntry(name: Self.parentName, isDirectory: true), at: 0) }
        if let name, let index = rows.firstIndex(where: { $0.name == name }) {
            cursor = index
        } else {
            cursor = min(cursor, max(rows.count - 1, 0))
        }
    }

    private func areInOrder(_ first: FileEntry, _ second: FileEntry) -> Bool {
        if dirsFirst && first.isDirectory != second.isDirectory { return first.isDirectory }
        let nameOptions: String.CompareOptions = caseSensitive ? [.numeric] : [.caseInsensitive, .numeric]
        let byName = { (first.name.compare(second.name, options: nameOptions) == .orderedAscending) }
        let result: Bool
        switch sortKey {
        case .name:
            result = byName()
        case .fileExtension:
            result = first.fileExtension == second.fileExtension ? byName() : first.fileExtension < second.fileExtension
        case .size:
            result = first.size == second.size ? byName() : first.size < second.size
        case .date, .accessTime, .changeTime, .creationTime:
            let firstDate = first.time(sortKey.entryTime) ?? .distantPast
            let secondDate = second.time(sortKey.entryTime) ?? .distantPast
            result = firstDate == secondDate ? byName() : firstDate < secondDate
        }
        return ascending ? result : !result
    }
}
