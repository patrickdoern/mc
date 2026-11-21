import CCurl
import Foundation

/// FTP und FTPS (implizit) über libcurl. Eine Verbindung wird über Aufrufe hinweg wiederverwendet.
/// Dateien werden über temporäre Dateien übertragen, weil libcurl Daten schiebt statt sie anzufordern.
public final class FTPFileSystem: FileSystem {
    public let identity: String
    public let displayName: String
    public private(set) var homePath = "/"
    private let target: FTPTarget
    private var password: String
    private var requiresTLS: Bool
    private var trustedNow = false
    private var limitedToTLS12 = false
    private let trustStore: FTPTrustStore
    private let handle: UnsafeMutableRawPointer
    private let lock = NSRecursiveLock()

    public init(target: FTPTarget, interaction: SSHInteraction, trustStore: FTPTrustStore = .standard) throws {
        guard let handle = curl_easy_init() else { throw FileError(localized("libcurl konnte nicht gestartet werden")) }
        self.handle = handle
        self.target = target
        self.trustStore = trustStore
        requiresTLS = target.user != "anonymous"
        identity = target.displayName
        displayName = target.displayName
        let account = target.displayName
        if target.user == "anonymous" {
            password = "anonymous@"
            do {
                try connect(interaction)
            } catch is FTPLoginError {
                throw FileError(localized("%@ erlaubt keine anonyme Anmeldung. Bitte mit Benutzer verbinden, z. B. %@", target.host as NSString, "\(target.secure ? "ftps" : "ftp")://name@\(target.host)" as NSString))
            }
            return
        }
        var stored = interaction.storedPassword(for: account)
        password = stored ?? ""
        while true {
            if stored == nil {
                guard let entry = interaction.requestPassword(localized("Passwort für %@:", account as NSString), account: account) else {
                    throw FileError(localized("Anmeldung abgebrochen"))
                }
                password = entry.password
                do {
                    try connect(interaction)
                } catch let error as FTPLoginError {
                    stored = nil
                    _ = error
                    continue
                }
                if entry.remember { interaction.savePassword(entry.password, for: account) }
                return
            }
            do {
                try connect(interaction)
                return
            } catch is FTPLoginError {
                interaction.deletePassword(for: account)
                stored = nil
            }
        }
    }

    deinit { curl_easy_cleanup(handle) }

    private func connect(_ interaction: SSHInteraction) throws {
        do {
            _ = try list("/")
        } catch is FTPWithoutTLS {
            guard interaction.allowUnencryptedLogin(target.host) else { throw FileError(localized("%@ bietet kein TLS an, Verbindung abgebrochen", target.host as NSString)) }
            requiresTLS = false
            try connect(interaction)
        } catch is FTPUntrustedCertificate {
            guard !trustedNow, let certificate = fetchCertificate() else { throw FileError(localized("Das Zertifikat von %@ ist nicht vertrauenswürdig", target.host as NSString)) }
            let changed = trustStore.trustedFile(host: target.host, port: target.port) != nil
            guard interaction.trustCertificate(target.host, certificate: certificate, changed: changed) else { throw OperationAborted() }
            try trustStore.trust(certificate, host: target.host, port: target.port)
            trustedNow = true
            try connect(interaction)
        }
    }

    private func fetchCertificate() -> FTPCertificate? {
        lock.lock()
        defer { lock.unlock() }
        prepare("/")
        _ = mc_curl_setopt_long(handle, CURLOPT_USE_SSL, Int(CURLUSESSL_ALL.rawValue))
        _ = mc_curl_setopt_long(handle, CURLOPT_SSL_VERIFYPEER, 0)
        _ = mc_curl_setopt_long(handle, CURLOPT_SSL_VERIFYHOST, 0)
        _ = mc_curl_setopt_long(handle, CURLOPT_CERTINFO, 1)
        _ = mc_curl_setopt_long(handle, CURLOPT_NOBODY, 1)
        _ = mc_curl_setopt_string(handle, CURLOPT_PINNEDPUBLICKEY, "sha256//" + String(repeating: "A", count: 43) + "=")
        _ = curl_easy_perform(handle)
        guard let info = mc_curl_certinfo(handle)?.pointee, info.num_of_certs > 0, let first = info.certinfo?[0] else { return nil }
        var entries: [String] = []
        var item: UnsafeMutablePointer<curl_slist>? = first
        while let current = item {
            if let data = current.pointee.data { entries.append(String(cString: data)) }
            item = current.pointee.next
        }
        return FTPCertificate(entries: entries)
    }

    // MARK: FileSystem

    public func list(_ path: String) throws -> [FileEntry] {
        let directory = path.hasSuffix("/") ? path : path + "/"
        if let data = try? perform(path: directory, customRequest: "MLSD"), let entries = Self.parseMLSD(data) { return entries }
        return Self.parseList(try perform(path: directory, customRequest: nil))
    }

    public func stat(_ path: String) throws -> FileEntry {
        if path == "/" { return FileEntry(name: "/", isDirectory: true, permissions: 0o755) }
        let name = PosixPath.name(path)
        guard let entry = try list(PosixPath.parent(path)).first(where: { $0.name == name }) else {
            throw FileError(localized("%@: Datei nicht gefunden", path as NSString))
        }
        return entry
    }

    public func makeDirectory(_ path: String) throws { try command(["MKD \(path)"], in: PosixPath.parent(path), path: path) }
    public func removeFile(_ path: String) throws { try command(["DELE \(path)"], in: PosixPath.parent(path), path: path) }
    public func removeDirectory(_ path: String) throws { try command(["RMD \(path)"], in: PosixPath.parent(path), path: path) }
    public func rename(_ from: String, _ to: String) throws { try command(["RNFR \(from)", "RNTO \(to)"], in: PosixPath.parent(from), path: from) }

    public func readLink(_ path: String) throws -> String { throw FileError(localized("%@: Symlinks gibt es über FTP nicht", path as NSString)) }
    public func makeSymlink(_ path: String, target: String) throws { throw FileError(localized("%@: Symlinks können über FTP nicht angelegt werden", path as NSString)) }
    public func setModified(_ path: String, _ date: Date) throws {}

    public func setPermissions(_ path: String, _ mode: UInt16) throws {
        try? command([String(format: "SITE CHMOD %o %@", mode & 0o777, path)], in: PosixPath.parent(path), path: path)
    }

    public func openReader(_ path: String) throws -> FileReader {
        let temporary = Self.temporaryFile()
        guard let file = fopen(temporary, "w+") else { throw FileError(path: temporary, errno: errno) }
        unlink(temporary)
        do {
            try download(path, to: file)
        } catch {
            fclose(file)
            throw error
        }
        rewind(file)
        return FTPDownload(file: file)
    }

    public func openWriter(_ path: String, permissions: UInt16) throws -> FileWriter {
        let temporary = Self.temporaryFile()
        guard let file = fopen(temporary, "w+") else { throw FileError(path: temporary, errno: errno) }
        unlink(temporary)
        return FTPUpload(owner: self, path: path, file: file)
    }

    // MARK: libcurl

    private struct Box { var data = Data() }

    private func baseURL(_ path: String) -> String {
        let encoded = path.split(separator: "/", omittingEmptySubsequences: true)
            .map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")
        let trailing = path.hasSuffix("/") && !encoded.isEmpty ? "/" : ""
        // Doppelter Schrägstrich nach dem Host: absoluter Pfad statt relativ zum Anmeldeordner.
        return "\(target.secure ? "ftps" : "ftp")://\(target.host):\(target.port)//\(encoded)\(trailing)"
    }

    private func prepare(_ path: String) {
        curl_easy_reset(handle)
        _ = mc_curl_setopt_string(handle, CURLOPT_URL, baseURL(path))
        _ = mc_curl_setopt_string(handle, CURLOPT_USERNAME, target.user)
        _ = mc_curl_setopt_string(handle, CURLOPT_PASSWORD, password)
        _ = mc_curl_setopt_long(handle, CURLOPT_CONNECTTIMEOUT, 20)
        _ = mc_curl_setopt_long(handle, CURLOPT_FTP_SKIP_PASV_IP, 1)
        _ = mc_curl_setopt_long(handle, CURLOPT_NOSIGNAL, 1)
        _ = mc_curl_setopt_long(handle, CURLOPT_MAXCONNECTS, 1)
        if let trusted = trustStore.trustedFile(host: target.host, port: target.port) {
            _ = mc_curl_setopt_string(handle, CURLOPT_CAINFO, trusted)
            _ = mc_curl_setopt_long(handle, CURLOPT_SSL_VERIFYHOST, 0)
        }
        if limitedToTLS12 {
            _ = mc_curl_setopt_long(handle, CURLOPT_SSLVERSION, Int(CURL_SSLVERSION_TLSv1_2) | Int(CURL_SSLVERSION_MAX_TLSv1_2))
        }
        if target.secure || requiresTLS {
            _ = mc_curl_setopt_long(handle, CURLOPT_USE_SSL, Int(CURLUSESSL_ALL.rawValue))
        } else {
            _ = mc_curl_setopt_long(handle, CURLOPT_USE_SSL, Int(CURLUSESSL_TRY.rawValue))
        }
    }

    private func failure(_ code: CURLcode, path: String) -> Error {
        switch code {
        case CURLE_LOGIN_DENIED: return FTPLoginError()
        case CURLE_USE_SSL_FAILED where requiresTLS && !target.secure: return FTPWithoutTLS()
        case CURLE_PEER_FAILED_VERIFICATION: return FTPUntrustedCertificate()
        case CURLE_REMOTE_FILE_NOT_FOUND: return FileError(localized("%@: Datei nicht gefunden", path as NSString))
        case CURLE_COULDNT_RESOLVE_HOST: return FileError(localized("Host %@ nicht gefunden", target.host as NSString))
        case CURLE_COULDNT_CONNECT: return FileError(localized("Keine Verbindung zu %@:%ld", target.host as NSString, target.port))
        case CURLE_OPERATION_TIMEDOUT: return FileError(localized("Zeitüberschreitung bei %@", target.host as NSString))
        case CURLE_REMOTE_ACCESS_DENIED: return FileError(localized("%@: Zugriff verweigert", path as NSString))
        case CURLE_QUOTE_ERROR: return FileError(localized("%@: Der Server hat den Befehl abgelehnt", path as NSString))
        default: return FileError("\(path): \(String(cString: curl_easy_strerror(code)))")
        }
    }

    private func perform(path: String, customRequest: String?) throws -> Data {
        lock.lock()
        defer { lock.unlock() }
        var box = Box()
        try withUnsafeMutablePointer(to: &box) { pointer in
            try transfer(path) {
                pointer.pointee.data = Data()
                if let customRequest { _ = mc_curl_setopt_string(handle, CURLOPT_CUSTOMREQUEST, customRequest) }
                _ = mc_curl_setopt_write(handle, { chunk, size, count, user in
                    guard let chunk, let user else { return 0 }
                    user.assumingMemoryBound(to: Box.self).pointee.data.append(UnsafeBufferPointer(start: UnsafeRawPointer(chunk).assumingMemoryBound(to: UInt8.self), count: size * count))
                    return size * count
                }, pointer)
            }
        }
        return box.data
    }

    private func transfer(_ path: String, configure: () -> Void) throws {
        prepare(path)
        configure()
        var code = curl_easy_perform(handle)
        if code != CURLE_OK, !limitedToTLS12, mc_curl_response_code(handle) == 425 {
            limitedToTLS12 = true
            prepare(path)
            configure()
            _ = mc_curl_setopt_long(handle, CURLOPT_FRESH_CONNECT, 1)
            code = curl_easy_perform(handle)
        }
        guard code == CURLE_OK else { throw failure(code, path: path) }
    }

    private func command(_ commands: [String], in directory: String, path: String) throws {
        lock.lock()
        defer { lock.unlock() }
        var list: UnsafeMutablePointer<curl_slist>?
        for command in commands { list = curl_slist_append(list, command) }
        defer { curl_slist_free_all(list) }
        prepare(directory.hasSuffix("/") ? directory : directory + "/")
        _ = mc_curl_setopt_long(handle, CURLOPT_NOBODY, 1)
        _ = mc_curl_setopt_slist(handle, CURLOPT_QUOTE, list)
        let code = curl_easy_perform(handle)
        guard code == CURLE_OK else { throw failure(code, path: path) }
    }

    private func download(_ path: String, to file: UnsafeMutablePointer<FILE>) throws {
        lock.lock()
        defer { lock.unlock() }
        try transfer(path) {
            rewind(file)
            ftruncate(fileno(file), 0)
            _ = mc_curl_setopt_write(handle, { chunk, size, count, user in
                guard let chunk, let user else { return 0 }
                return fwrite(chunk, size, count, user.assumingMemoryBound(to: FILE.self))
            }, file)
        }
    }

    fileprivate func upload(_ file: UnsafeMutablePointer<FILE>, to path: String) throws {
        lock.lock()
        defer { lock.unlock() }
        fflush(file)
        let size = ftell(file)
        try transfer(path) {
            rewind(file)
            _ = mc_curl_setopt_long(handle, CURLOPT_UPLOAD, 1)
            _ = mc_curl_setopt_long(handle, CURLOPT_FTP_CREATE_MISSING_DIRS, 0)
            _ = mc_curl_setopt_offset(handle, CURLOPT_INFILESIZE_LARGE, curl_off_t(size))
            _ = mc_curl_setopt_read(handle, { buffer, size, count, user in
                guard let buffer, let user else { return 0 }
                return fread(buffer, size, count, user.assumingMemoryBound(to: FILE.self))
            }, file)
        }
    }

    private static func temporaryFile() -> String {
        NSTemporaryDirectory() + "moonlight-ftp-" + UUID().uuidString
    }

    // MARK: Listen parsen

    static func parseMLSD(_ data: Data) -> [FileEntry]? {
        let text = String(decoding: data, as: UTF8.self)
        var entries: [FileEntry] = []
        for line in text.split(whereSeparator: \.isNewline) {
            guard let separator = line.range(of: "; ") else { return nil }
            let name = String(line[separator.upperBound...])
            var facts: [String: String] = [:]
            for fact in line[..<separator.lowerBound].split(separator: ";") {
                let pair = fact.split(separator: "=", maxSplits: 1)
                if pair.count == 2 { facts[pair[0].lowercased()] = String(pair[1]) }
            }
            guard let type = facts["type"]?.lowercased() else { return nil }
            if type == "cdir" || type == "pdir" || name == "." || name == ".." { continue }
            entries.append(FileEntry(
                name: name,
                isDirectory: type == "dir",
                isSymlink: type.hasPrefix("os.unix=slink"),
                size: Int64(facts["size"] ?? "") ?? 0,
                modified: facts["modify"].flatMap(parseMLSDDate),
                permissions: facts["unix.mode"].flatMap { UInt16($0, radix: 8) } ?? (type == "dir" ? 0o755 : 0o644)
            ))
        }
        return entries
    }

    private static func parseMLSDDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = text.contains(".") ? "yyyyMMddHHmmss.SSS" : "yyyyMMddHHmmss"
        return formatter.date(from: text)
    }

    /// Unix-Format von `ls -l`; DOS/IIS-Listen werden nicht erkannt und ergeben keine Einträge.
    static func parseList(_ data: Data) -> [FileEntry] {
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        var entries: [FileEntry] = []
        for line in String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: true)
            guard parts.count == 9, parts[0].count >= 10, "-dlbcps".contains(parts[0].first!), let month = months.firstIndex(of: String(parts[5])) else { continue }
            var name = String(parts[8])
            let isLink = parts[0].hasPrefix("l")
            if isLink, let arrow = name.range(of: " -> ") { name = String(name[..<arrow.lowerBound]) }
            if name == "." || name == ".." { continue }
            var components = DateComponents(month: month + 1, day: Int(parts[6]))
            if parts[7].contains(":") {
                let clock = parts[7].split(separator: ":")
                components.hour = Int(clock[0])
                components.minute = Int(clock[1])
                components.year = calendar.component(.year, from: now)
                if let date = calendar.date(from: components), date > now.addingTimeInterval(86_400) { components.year! -= 1 }
            } else {
                components.year = Int(parts[7])
            }
            let mode = parts[0].dropFirst().prefix(9)
            var permissions: UInt16 = 0
            for (index, character) in mode.enumerated() where character != "-" { permissions |= 1 << UInt16(8 - index) }
            entries.append(FileEntry(
                name: name,
                isDirectory: parts[0].hasPrefix("d"),
                isSymlink: isLink,
                size: Int64(parts[4]) ?? 0,
                modified: calendar.date(from: components),
                permissions: permissions
            ))
        }
        return entries
    }
}

private struct FTPLoginError: Error {}

private struct FTPWithoutTLS: Error {}

private struct FTPUntrustedCertificate: Error {}

private final class FTPDownload: FileReader {
    private var file: UnsafeMutablePointer<FILE>?

    init(file: UnsafeMutablePointer<FILE>) { self.file = file }

    deinit { close() }

    func read(into buffer: UnsafeMutableRawBufferPointer) throws -> Int {
        guard let file else { return 0 }
        return fread(buffer.baseAddress, 1, buffer.count, file)
    }

    func close() {
        if let file { fclose(file) }
        file = nil
    }
}

private final class FTPUpload: FileWriter {
    private let owner: FTPFileSystem
    private let path: String
    private var file: UnsafeMutablePointer<FILE>?

    init(owner: FTPFileSystem, path: String, file: UnsafeMutablePointer<FILE>) {
        self.owner = owner
        self.path = path
        self.file = file
    }

    deinit { abort() }

    func write(_ buffer: UnsafeRawBufferPointer) throws {
        guard let file else { return }
        guard fwrite(buffer.baseAddress, 1, buffer.count, file) == buffer.count else { throw FileError(localized("%@: Temporäre Datei nicht beschreibbar", path as NSString)) }
    }

    func finish() throws {
        guard let file else { return }
        self.file = nil
        defer { fclose(file) }
        try owner.upload(file, to: path)
    }

    func abort() {
        if let file { fclose(file) }
        file = nil
    }
}
