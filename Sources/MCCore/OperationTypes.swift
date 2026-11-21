import Foundation

public struct Transfer: Sendable {
    public let source: String
    public let destination: String

    public init(source: String, destination: String) {
        self.source = source
        self.destination = destination
    }
}

public struct OperationProgress: Sendable {
    public var currentPath = ""
    public var bytesDone: Int64 = 0
    public var bytesTotal: Int64 = 0
    public var filesDone = 0
    public var filesTotal = 0
}

public struct ConflictInfo: Sendable {
    public let path: String
    public let source: FileEntry
    public let existing: FileEntry
}

public enum OverwriteRule: Int, Sendable {
    case ask, overwrite, ifNewer, ifSizeDiffers, skip
}

public struct TransferOptions: Sendable {
    public var overwriteRule: OverwriteRule
    public var preserveAttributes: Bool
    public var followSymlinks: Bool

    public init(overwriteRule: OverwriteRule = .ask, preserveAttributes: Bool = true, followSymlinks: Bool = false) {
        self.overwriteRule = overwriteRule
        self.preserveAttributes = preserveAttributes
        self.followSymlinks = followSymlinks
    }
}

public enum ConflictChoice: Sendable {
    case overwrite, overwriteAll, skip, skipAll, cancel
    case overwriteThenRule(OverwriteRule), skipThenRule(OverwriteRule)
}

public enum FailureChoice: Sendable {
    case skip, skipAll, abort
}

public struct OperationAborted: Error {
    public init() {}
}

public struct OperationHandlers {
    public var progress: (OperationProgress) -> Void
    public var resolveConflict: (ConflictInfo) -> ConflictChoice
    public var resolveFailure: (String, Error) -> FailureChoice

    public init(
        progress: @escaping (OperationProgress) -> Void,
        resolveConflict: @escaping (ConflictInfo) -> ConflictChoice,
        resolveFailure: @escaping (String, Error) -> FailureChoice
    ) {
        self.progress = progress
        self.resolveConflict = resolveConflict
        self.resolveFailure = resolveFailure
    }
}
