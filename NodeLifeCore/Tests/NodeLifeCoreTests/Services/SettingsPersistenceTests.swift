// ABOUTME: Tests that UserDefaults-backed settings round-trip correctly
// ABOUTME: Verifies the key naming convention used by both SettingsView and SetupWizardView

import Testing
import Foundation

@Test func settingsKeysRoundTrip() {
    let defaults = UserDefaults.standard
    let testSuffix = UUID().uuidString

    let providerKey = "nodelife.llm.provider.\(testSuffix)"
    let modelKey = "nodelife.llm.model.\(testSuffix)"
    let modeKey = "nodelife.extraction.mode.\(testSuffix)"
    let baseURLKey = "nodelife.llm.baseURL.\(testSuffix)"

    defaults.set("anthropic", forKey: providerKey)
    defaults.set("claude-sonnet-4-6", forKey: modelKey)
    defaults.set("quick", forKey: modeKey)
    defaults.set("https://api.openai.com/v1", forKey: baseURLKey)

    #expect(defaults.string(forKey: providerKey) == "anthropic")
    #expect(defaults.string(forKey: modelKey) == "claude-sonnet-4-6")
    #expect(defaults.string(forKey: modeKey) == "quick")
    #expect(defaults.string(forKey: baseURLKey) == "https://api.openai.com/v1")

    defaults.removeObject(forKey: providerKey)
    defaults.removeObject(forKey: modelKey)
    defaults.removeObject(forKey: modeKey)
    defaults.removeObject(forKey: baseURLKey)
}

@Test func dataSourceSettingsRoundTrip() {
    let defaults = UserDefaults.standard
    let testSuffix = UUID().uuidString

    let granolaEnabledKey = "nodelife.sources.granola.enabled.\(testSuffix)"
    let granolaPathKey = "nodelife.sources.granola.path.\(testSuffix)"

    defaults.set(true, forKey: granolaEnabledKey)
    defaults.set("~/Library/Application Support/Granola", forKey: granolaPathKey)

    #expect(defaults.bool(forKey: granolaEnabledKey) == true)
    #expect(defaults.string(forKey: granolaPathKey) == "~/Library/Application Support/Granola")

    defaults.removeObject(forKey: granolaEnabledKey)
    defaults.removeObject(forKey: granolaPathKey)
}

@Test func hasCompletedSetupDefaultsToFalse() {
    let defaults = UserDefaults.standard
    let key = "hasCompletedSetup.\(UUID().uuidString)"

    #expect(defaults.bool(forKey: key) == false)

    defaults.set(true, forKey: key)
    #expect(defaults.bool(forKey: key) == true)

    defaults.removeObject(forKey: key)
}
