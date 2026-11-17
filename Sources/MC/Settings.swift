import Foundation

enum Settings {
    private static let defaults = UserDefaults.standard

    static var useTrash: Bool {
        get { defaults.object(forKey: "useTrash") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "useTrash") }
    }

    static var confirmDelete: Bool {
        get { defaults.object(forKey: "confirmDelete") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "confirmDelete") }
    }

    static var confirmOverwrite: Bool {
        get { defaults.object(forKey: "confirmOverwrite") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "confirmOverwrite") }
    }

    static var confirmExit: Bool {
        get { defaults.bool(forKey: "confirmExit") }
        set { defaults.set(newValue, forKey: "confirmExit") }
    }

    static var verticalLayout: Bool {
        get { defaults.bool(forKey: "verticalLayout") }
        set { defaults.set(newValue, forKey: "verticalLayout") }
    }

    static var showMenuLine: Bool {
        get { defaults.object(forKey: "showMenuLine") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showMenuLine") }
    }

    static var showCommandLine: Bool {
        get { defaults.object(forKey: "showCommandLine") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showCommandLine") }
    }

    static var showKeyBar: Bool {
        get { defaults.object(forKey: "showKeyBar") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showKeyBar") }
    }

    static var scheme: Int {
        get { defaults.integer(forKey: "scheme") }
        set { defaults.set(newValue, forKey: "scheme") }
    }

    static var hotlist: [String] {
        get { defaults.stringArray(forKey: "hotlist") ?? [] }
        set { defaults.set(newValue, forKey: "hotlist") }
    }
}

enum Shell {
    static func quote(_ text: String) -> String {
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./-+@%:,=")
        guard text.unicodeScalars.contains(where: { !safe.contains($0) }) else { return text }
        return "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
