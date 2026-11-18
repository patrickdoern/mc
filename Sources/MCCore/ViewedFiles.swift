import Foundation

public struct ViewedFile: Equatable {
    public let path: String
    public let edited: Bool

    public init(path: String, edited: Bool) {
        self.path = path
        self.edited = edited
    }

    public init?(encoded: String) {
        guard let separator = encoded.firstIndex(of: "\t"), ["e", "v"].contains(encoded[..<separator]) else { return nil }
        path = String(encoded[encoded.index(after: separator)...])
        edited = encoded[..<separator] == "e"
    }

    public var encoded: String { (edited ? "e" : "v") + "\t" + path }
}

public enum ViewedFiles {
    public static let limit = 30

    public static func recording(_ file: ViewedFile, in files: [ViewedFile]) -> [ViewedFile] {
        Array(([file] + files.filter { $0.path != file.path }).prefix(limit))
    }
}
