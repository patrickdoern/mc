import Foundation

public enum TokenKind: Sendable {
    case keyword, string, comment, number, type, property, addition, deletion
}

public struct SyntaxToken: Equatable, Sendable {
    public let range: NSRange
    public let kind: TokenKind
}

struct SyntaxLanguage {
    var keywords: [String] = []
    var caseInsensitiveKeywords = false
    var highlightsTypes = false
    var highlightsNumbers = true
    var lineComments: [String] = []
    var blockComment: (open: String, close: String)?
    var tripleQuotes = false
    var quotes: [Character] = ["\"", "'"]
    var rules: [(pattern: String, kind: TokenKind)] = []
    var rulesAfterStrings: [(pattern: String, kind: TokenKind)] = []
}

public final class SyntaxHighlighter {
    public static let maximumLength = 1_500_000

    private struct Compiled {
        let before: [(NSRegularExpression, TokenKind)]
        let literals: NSRegularExpression?
        let literalKinds: [TokenKind]
        let after: [(NSRegularExpression, TokenKind)]
    }

    private static var cache: [String: Compiled] = [:]
    private static let lock = NSLock()

    public static func languageName(forFile name: String, firstLine: String) -> String? {
        let lower = name.lowercased()
        let byName = ["makefile": "shell", "dockerfile": "shell", ".zshrc": "shell", ".bashrc": "shell", ".zprofile": "shell", ".profile": "shell", ".gitignore": "shell"]
        if let language = byName[lower] { return language }
        let ext = lower.contains(".") ? String(lower.split(separator: ".").last ?? "") : ""
        let byExtension: [String: String] = [
            "swift": "swift", "js": "js", "mjs": "js", "cjs": "js", "jsx": "js", "ts": "js", "tsx": "js", "php": "php", "phtml": "php", "py": "python",
            "rb": "ruby", "rake": "ruby", "gemspec": "ruby", "sh": "shell", "bash": "shell", "zsh": "shell", "command": "shell", "c": "c", "h": "c",
            "cpp": "c", "cc": "c", "hpp": "c", "hh": "c", "m": "c", "mm": "c", "cs": "c", "java": "java", "kt": "kotlin", "kts": "kotlin", "go": "go",
            "rs": "rust", "sql": "sql", "dart": "dart", "json": "json", "jsonc": "json", "yaml": "yaml", "yml": "yaml", "toml": "ini", "ini": "ini",
            "conf": "ini", "cfg": "ini", "html": "markup", "htm": "markup", "xml": "markup", "svg": "markup", "plist": "markup", "xhtml": "markup",
            "css": "css", "scss": "css", "less": "css", "md": "markdown", "markdown": "markdown", "diff": "diff", "patch": "diff",
        ]
        if let language = byExtension[ext] { return language }
        guard firstLine.hasPrefix("#!") else { return nil }
        for (needle, language) in [("python", "python"), ("ruby", "ruby"), ("node", "js"), ("php", "php"), ("sh", "shell")] where firstLine.contains(needle) { return language }
        return nil
    }

    public static func tokens(in text: String, language name: String) -> [SyntaxToken] {
        guard let compiled = compiled(for: name) else { return [] }
        let string = text as NSString
        let full = NSRange(location: 0, length: string.length)
        var tokens: [SyntaxToken] = []
        for (regex, kind) in compiled.before {
            regex.enumerateMatches(in: text, range: full) { match, _, _ in
                if let range = match?.range, range.length > 0 { tokens.append(SyntaxToken(range: range, kind: kind)) }
            }
        }
        if let literals = compiled.literals {
            literals.enumerateMatches(in: text, range: full) { match, _, _ in
                guard let match else { return }
                for (index, kind) in compiled.literalKinds.enumerated() where match.range(at: index + 1).location != NSNotFound {
                    tokens.append(SyntaxToken(range: match.range(at: index + 1), kind: kind))
                    return
                }
            }
        }
        for (regex, kind) in compiled.after {
            regex.enumerateMatches(in: text, range: full) { match, _, _ in
                if let range = match?.range, range.length > 0 { tokens.append(SyntaxToken(range: range, kind: kind)) }
            }
        }
        return tokens
    }

    private static func compiled(for name: String) -> Compiled? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[name] { return cached }
        guard let language = languages[name] else { return nil }
        let result = compile(language)
        cache[name] = result
        return result
    }

    private static func regex(_ pattern: String, caseInsensitive: Bool = false) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.anchorsMatchLines, .caseInsensitive] : [.anchorsMatchLines])
    }

    private static func compile(_ language: SyntaxLanguage) -> Compiled {
        var before: [(NSRegularExpression, TokenKind)] = []
        func add(_ pattern: String, _ kind: TokenKind, caseInsensitive: Bool = false) {
            if let expression = regex(pattern, caseInsensitive: caseInsensitive) { before.append((expression, kind)) }
        }
        if language.highlightsNumbers { add(#"\b(?:0[xX][0-9a-fA-F_]+|\d[\d_]*(?:\.\d+)?(?:[eE][+-]?\d+)?)\b"#, .number) }
        if language.highlightsTypes { add(#"\b[A-Z][A-Za-z0-9_]*\b"#, .type) }
        if !language.keywords.isEmpty {
            add(#"(?<![\w$])(?:"# + language.keywords.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|") + #")(?![\w$])"#, .keyword, caseInsensitive: language.caseInsensitiveKeywords)
        }
        for rule in language.rules { add(rule.pattern, rule.kind) }

        var alternatives: [(String, TokenKind)] = []
        if let block = language.blockComment {
            alternatives.append((NSRegularExpression.escapedPattern(for: block.open) + #"[\s\S]*?(?:"# + NSRegularExpression.escapedPattern(for: block.close) + "|\\z)", .comment))
        }
        for marker in language.lineComments { alternatives.append((NSRegularExpression.escapedPattern(for: marker) + #"[^\n]*"#, .comment)) }
        if language.tripleQuotes {
            alternatives.append((#"""[\s\S]*?(?:"""|\z)"#, .string))
            alternatives.append((#"'''[\s\S]*?(?:'''|\z)"#, .string))
        }
        for quote in language.quotes {
            let escaped = NSRegularExpression.escapedPattern(for: String(quote))
            alternatives.append((escaped + #"(?:\\.|[^"# + escaped + #"\\\n])*"# + escaped + "?", .string))
        }
        let literals = alternatives.isEmpty ? nil : regex(alternatives.map { "(" + $0.0 + ")" }.joined(separator: "|"))
        let after = language.rulesAfterStrings.compactMap { rule in regex(rule.pattern).map { ($0, rule.kind) } }
        return Compiled(before: before, literals: literals, literalKinds: alternatives.map(\.1), after: after)
    }

    private static let cFamilyComments = (lines: ["//"], block: (open: "/*", close: "*/"))

    private static let languages: [String: SyntaxLanguage] = [
        "swift": SyntaxLanguage(
            keywords: "associatedtype class deinit enum extension fileprivate func import init inout internal let open operator private protocol public rethrows static struct subscript typealias var break case catch continue default defer do else fallthrough for guard if in repeat return throw switch where while Any as await false is nil self Self super throws true try async actor some any override final lazy weak mutating nonmutating indirect convenience required".split(separator: " ").map(String.init),
            highlightsTypes: true, lineComments: ["//"], blockComment: ("/*", "*/"), tripleQuotes: true, quotes: ["\""], rules: [(#"@\w+|#\w+"#, .property)]),
        "js": SyntaxLanguage(
            keywords: "break case catch class const continue debugger default delete do else export extends finally for function if import in instanceof let new return super switch this throw try typeof var void while with yield async await of static get set null undefined true false interface type enum implements namespace declare readonly private protected public abstract as from".split(separator: " ").map(String.init),
            highlightsTypes: true, lineComments: ["//"], blockComment: ("/*", "*/"), quotes: ["\"", "'", "`"]),
        "php": SyntaxLanguage(
            keywords: "abstract and array as break callable case catch class clone const continue declare default do echo else elseif empty extends final finally fn for foreach function global if implements include include_once instanceof interface isset list match namespace new or print private protected public readonly require require_once return static switch throw trait try unset use var while xor yield true false null self parent".split(separator: " ").map(String.init),
            highlightsTypes: true, lineComments: ["//", "#"], blockComment: ("/*", "*/"), rules: [(#"\$\w+"#, .property), (#"<\?php|\?>"#, .keyword)]),
        "python": SyntaxLanguage(
            keywords: "and as assert async await break class continue def del elif else except finally for from global if import in is lambda nonlocal not or pass raise return try while with yield True False None self".split(separator: " ").map(String.init),
            highlightsTypes: false, lineComments: ["#"], tripleQuotes: true, rules: [(#"@\w+"#, .property)]),
        "ruby": SyntaxLanguage(
            keywords: "alias and begin break case class def do else elsif end ensure false for if in module next nil not or redo rescue retry return self super then true undef unless until when while yield require include extend attr_accessor attr_reader attr_writer puts".split(separator: " ").map(String.init),
            highlightsTypes: true, lineComments: ["#"], rules: [(#":[A-Za-z_]\w*"#, .property), (#"@{1,2}\w+"#, .property)]),
        "shell": SyntaxLanguage(
            keywords: "if then else elif fi for while until do done case esac in function select time return exit break continue local export readonly declare unset shift source alias echo cd test true false".split(separator: " ").map(String.init),
            highlightsNumbers: false, lineComments: ["#"], quotes: ["\"", "'"], rules: [(#"\$(?:\w+|\{[^}\n]*\}|[@#?$!*0-9])"#, .property)]),
        "c": SyntaxLanguage(
            keywords: "auto break case char const continue default do double else enum extern float for goto if inline int long register restrict return short signed sizeof static struct switch typedef union unsigned void volatile while bool true false NULL nullptr class namespace template typename public private protected virtual new delete using this try catch throw override final constexpr noexcept interface string var foreach readonly abstract sealed null base".split(separator: " ").map(String.init),
            highlightsTypes: true, lineComments: ["//"], blockComment: ("/*", "*/"), rules: [(#"^\s*#\s*\w+"#, .property), (#"@\w+"#, .property)]),
        "java": SyntaxLanguage(
            keywords: "abstract assert boolean break byte case catch char class const continue default do double else enum extends final finally float for goto if implements import instanceof int interface long native new package private protected public return short static strictfp super switch synchronized this throw throws transient try void volatile while true false null var record".split(separator: " ").map(String.init),
            highlightsTypes: true, lineComments: ["//"], blockComment: ("/*", "*/"), rules: [(#"@\w+"#, .property)]),
        "kotlin": SyntaxLanguage(
            keywords: "as break class continue do else false for fun if in interface is null object package return super this throw true try typealias typeof val var when while by catch constructor finally import init abstract annotation companion const data enum external final infix inline inner internal lateinit open operator out override private protected public sealed suspend vararg".split(separator: " ").map(String.init),
            highlightsTypes: true, lineComments: ["//"], blockComment: ("/*", "*/"), tripleQuotes: true, quotes: ["\""], rules: [(#"@\w+"#, .property)]),
        "go": SyntaxLanguage(
            keywords: "break default func interface select case defer go map struct chan else goto package switch const fallthrough if range type continue for import return var true false nil".split(separator: " ").map(String.init),
            highlightsTypes: true, lineComments: ["//"], blockComment: ("/*", "*/"), quotes: ["\"", "'", "`"]),
        "rust": SyntaxLanguage(
            keywords: "as async await break const continue crate dyn else enum extern false fn for if impl in let loop match mod move mut pub ref return self Self static struct super trait true type unsafe use where while".split(separator: " ").map(String.init),
            highlightsTypes: true, lineComments: ["//"], blockComment: ("/*", "*/"), quotes: ["\""], rules: [(#"#!?\[[^\]\n]*\]"#, .property)]),
        "sql": SyntaxLanguage(
            keywords: "select from where and or not insert into values update set delete create table alter drop index join left right inner outer on group by order having limit offset as distinct union all null is in like between exists case when then else end primary key foreign references default unique constraint database view if begin commit rollback".split(separator: " ").map(String.init),
            caseInsensitiveKeywords: true, lineComments: ["--"], blockComment: ("/*", "*/"), quotes: ["'", "\""]),
        "dart": SyntaxLanguage(
            keywords: "abstract as assert async await break case catch class const continue covariant default deferred do dynamic else enum export extends extension external factory false final finally for Function get hide if implements import in interface is late library mixin new null on operator part required rethrow return set show static super switch sync this throw true try typedef var void while with yield".split(separator: " ").map(String.init),
            highlightsTypes: true, lineComments: ["//"], blockComment: ("/*", "*/"), rules: [(#"@\w+"#, .property)]),
        "json": SyntaxLanguage(
            keywords: ["true", "false", "null"], quotes: ["\""], rulesAfterStrings: [(#""(?:\\.|[^"\\\n])*"(?=\s*:)"#, .property)]),
        "yaml": SyntaxLanguage(
            keywords: ["true", "false", "null", "yes", "no", "on", "off"], lineComments: ["#"], rules: [(#"^\s*-?\s*[\w.\-/]+(?=\s*:)"#, .property)]),
        "ini": SyntaxLanguage(
            keywords: ["true", "false", "yes", "no", "on", "off"], lineComments: ["#", ";"], rules: [(#"^\s*\[[^\]\n]*\]"#, .keyword), (#"^\s*[\w.\-]+(?=\s*=)"#, .property)]),
        "markup": SyntaxLanguage(
            highlightsNumbers: false, blockComment: ("<!--", "-->"), rules: [(#"</?[A-Za-z][\w:\-.]*|/?>|<\?[\w\-]+|\?>|<!DOCTYPE"#, .keyword), (#"[\w:\-]+(?=\s*=)"#, .property)]),
        "css": SyntaxLanguage(
            blockComment: ("/*", "*/"), rules: [(#"#[0-9a-fA-F]{3,8}\b"#, .number), (#"@[\w\-]+"#, .keyword), (#"[\w\-]+(?=\s*:)"#, .property), (#"[.#][A-Za-z_][\w\-]*"#, .type)]),
        "diff": SyntaxLanguage(
            highlightsNumbers: false, quotes: [], rules: [(#"^\+.*$"#, .addition), (#"^-.*$"#, .deletion), (#"^(?:\+\+\+|---) .*$"#, .keyword), (#"^@@.*$"#, .property)]),
        "markdown": SyntaxLanguage(
            highlightsNumbers: false, quotes: [], rules: [(#"^#{1,6}\s.*$"#, .keyword), (#"^\s*(?:[-*+]|\d+\.)\s"#, .number), (#"`[^`\n]+`"#, .string), (#"\[[^\]\n]*\]\([^)\n]*\)"#, .property), (#"^```.*$"#, .comment)]),
    ]
}
