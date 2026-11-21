import Foundation
import Testing
@testable import MCCore

@Suite struct LocalizationTests {
    @Test func detectsLanguageFromPreferredLanguages() {
        #expect(Localization.detectLanguage(["de-DE", "en"]) == .german)
        #expect(Localization.detectLanguage(["en-US"]) == .english)
        #expect(Localization.detectLanguage(["fr-FR", "de"]) == .german)
        #expect(Localization.detectLanguage(["fr"]) == .english)
        #expect(Localization.detectLanguage(["de_AT"]) == .german)
        #expect(Localization.detectLanguage([]) == .english)
    }

    @Test func detectsLanguageCaseInsensitively() {
        #expect(Localization.detectLanguage(["DE-de"]) == .german)
        #expect(Localization.detectLanguage(["EN-us", "de"]) == .english)
    }

    @Test func looksUpEnglishTranslation() {
        let localization = Localization(language: .english, table: ["Abbrechen": "Cancel"])
        #expect(localization.text("Abbrechen") == "Cancel")
    }

    @Test func keepsGermanKeyWithoutEntry() {
        let localization = Localization(language: .english, table: ["Abbrechen": "Cancel"])
        #expect(localization.text("Löschen") == "Löschen")
        #expect(Localization(language: .english, table: [:]).text("Löschen") == "Löschen")
    }

    @Test func keepsGermanKeyForEmptyEntry() {
        let localization = Localization(language: .english, table: ["Löschen": ""])
        #expect(localization.text("Löschen") == "Löschen")
    }

    @Test func formatsArguments() {
        let localization = Localization(
            language: .english,
            table: [
                "%@ kopieren": "Copy %@",
                "%d Dateien": "%d files",
                "%1$@ nach %2$@": "%2$@ from %1$@",
            ]
        )
        #expect(localization.text("%@ kopieren", ["a.txt" as NSString]) == "Copy a.txt")
        #expect(localization.text("%d Dateien", [3]) == "3 files")
        #expect(localization.text("%1$@ nach %2$@", ["A" as NSString, "B" as NSString]) == "B from A")
    }

    @Test func formatsGermanKeyWithoutTable() {
        let localization = Localization(language: .german, table: [:])
        #expect(localization.text("%d Dateien", [3]) == "3 Dateien")
    }

    @Test func germanReturnsKeyEvenWithTableEntry() {
        let localization = Localization(language: .german, table: ["Abbrechen": "Cancel"])
        #expect(localization.text("Abbrechen") == "Abbrechen")
    }

    @Test func publicFunctionFallsBackToKeyWithoutBundleTable() {
        #expect(localized("Abbrechen") == "Abbrechen")
        #expect(localized("%d Dateien", 2) == "2 Dateien")
    }
}
