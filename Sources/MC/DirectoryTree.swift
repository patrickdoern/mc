import Foundation
import MCCore

final class DirectoryTree {
    struct Row {
        let path: String
        let name: String
        let depth: Int
        let isExpanded: Bool
        let isLeaf: Bool
    }

    private(set) var rows: [Row] = []
    var cursor = 0

    private let fileSystem: FileSystem
    private let showHidden: Bool
    private let onChange: () -> Void
    private var children: [String: [String]] = [:]
    private var expanded: Set<String> = ["/"]

    init(fileSystem: FileSystem, path: String, showHidden: Bool, onChange: @escaping () -> Void) {
        self.fileSystem = fileSystem
        self.showHidden = showHidden
        self.onChange = onChange
        rebuild(keeping: nil)
        let chain = Self.ancestors(of: path)
        expanded.formUnion(chain)
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let loaded = Dictionary(uniqueKeysWithValues: chain.map { ($0, directories(in: $0)) })
            DispatchQueue.main.async { [self] in
                children.merge(loaded) { _, new in new }
                rebuild(keeping: path)
                onChange()
            }
        }
    }

    var currentPath: String? { rows.indices.contains(cursor) ? rows[cursor].path : nil }

    func expand() {
        guard let row = rows.indices.contains(cursor) ? rows[cursor] : nil, !row.isExpanded else { return }
        expanded.insert(row.path)
        guard children[row.path] == nil else {
            rebuild(keeping: row.path)
            onChange()
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let loaded = directories(in: row.path)
            DispatchQueue.main.async { [self] in
                children[row.path] = loaded
                rebuild(keeping: row.path)
                onChange()
            }
        }
    }

    func collapse() {
        guard let row = rows.indices.contains(cursor) ? rows[cursor] : nil else { return }
        if row.isExpanded && row.path != "/" {
            expanded.remove(row.path)
            rebuild(keeping: row.path)
        } else if let parent = rows[..<cursor].last(where: { $0.depth < row.depth }) {
            cursor = rows.firstIndex { $0.path == parent.path } ?? cursor
        }
        onChange()
    }

    func move(by delta: Int) {
        cursor = min(max(cursor + delta, 0), max(rows.count - 1, 0))
        onChange()
    }

    private func directories(in path: String) -> [String] {
        ((try? fileSystem.list(path)) ?? [])
            .filter { $0.isDirectory && !$0.isSymlink && (showHidden || !$0.isHidden) }
            .map(\.name)
            .sorted { $0.compare($1, options: [.caseInsensitive, .numeric]) == .orderedAscending }
    }

    private func rebuild(keeping path: String?) {
        rows = []
        append("/", name: "/", depth: 0)
        if let path, let index = rows.firstIndex(where: { $0.path == path }) { cursor = index } else { cursor = min(cursor, max(rows.count - 1, 0)) }
    }

    private func append(_ path: String, name: String, depth: Int) {
        let isOpen = expanded.contains(path)
        rows.append(Row(path: path, name: name, depth: depth, isExpanded: isOpen, isLeaf: children[path]?.isEmpty == true))
        guard isOpen, let names = children[path] else { return }
        for child in names { append(PosixPath.join(path, child), name: child, depth: depth + 1) }
    }

    private static func ancestors(of path: String) -> [String] {
        var result = ["/"]
        var current = ""
        for component in path.split(separator: "/") {
            current += "/" + component
            result.append(current)
        }
        return result
    }
}
