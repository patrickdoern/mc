import Testing
@testable import MCCore

@Suite struct AppLanguagePreferenceTests {
    @Test func detectsGerman() {
        #expect(AppLanguagePreference(stored: ["de"]) == .german)
        #expect(AppLanguagePreference(stored: ["de-DE", "en"]) == .german)
    }

    @Test func detectsEnglish() {
        #expect(AppLanguagePreference(stored: ["en"]) == .english)
        #expect(AppLanguagePreference(stored: ["EN-us"]) == .english)
    }

    @Test func fallsBackToAutomatic() {
        #expect(AppLanguagePreference(stored: nil) == .automatic)
        #expect(AppLanguagePreference(stored: []) == .automatic)
        #expect(AppLanguagePreference(stored: ["fr"]) == .automatic)
        #expect(AppLanguagePreference(stored: ["xx"]) == .automatic)
        #expect(AppLanguagePreference(stored: [""]) == .automatic)
    }

    @Test func onlyFirstEntryCounts() {
        #expect(AppLanguagePreference(stored: ["fr", "de"]) == .automatic)
    }

    @Test func providesStoredList() {
        #expect(AppLanguagePreference.automatic.stored == nil)
        #expect(AppLanguagePreference.german.stored == ["de"])
        #expect(AppLanguagePreference.english.stored == ["en"])
    }

    @Test func roundTripsAllCases() {
        for preference in AppLanguagePreference.allCases {
            #expect(AppLanguagePreference(stored: preference.stored) == preference)
        }
    }
}
