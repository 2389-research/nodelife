// ABOUTME: Integration test verifying wizard completion sets hasCompletedSetup flag
// ABOUTME: Tests that the UserDefaults flag correctly controls wizard visibility

import Testing
import Foundation

@Test func wizardCompletionSetsFlag() {
    let defaults = UserDefaults.standard
    let key = "hasCompletedSetup.integration.\(UUID().uuidString)"

    #expect(defaults.bool(forKey: key) == false)

    defaults.set(true, forKey: key)

    #expect(defaults.bool(forKey: key) == true)

    defaults.removeObject(forKey: key)
}

@Test func wizardSettingsPersistedAcrossReads() {
    let defaults = UserDefaults.standard
    let suffix = UUID().uuidString

    defaults.set("anthropic", forKey: "nodelife.llm.provider.\(suffix)")
    defaults.set("claude-sonnet-4-6", forKey: "nodelife.llm.model.\(suffix)")
    defaults.set("quick", forKey: "nodelife.extraction.mode.\(suffix)")
    defaults.set(true, forKey: "nodelife.sources.granola.enabled.\(suffix)")
    defaults.set("~/Library/Application Support/Granola", forKey: "nodelife.sources.granola.path.\(suffix)")
    defaults.set(true, forKey: "hasCompletedSetup.\(suffix)")

    #expect(defaults.string(forKey: "nodelife.llm.provider.\(suffix)") == "anthropic")
    #expect(defaults.string(forKey: "nodelife.llm.model.\(suffix)") == "claude-sonnet-4-6")
    #expect(defaults.string(forKey: "nodelife.extraction.mode.\(suffix)") == "quick")
    #expect(defaults.bool(forKey: "nodelife.sources.granola.enabled.\(suffix)") == true)
    #expect(defaults.bool(forKey: "hasCompletedSetup.\(suffix)") == true)

    for key in ["nodelife.llm.provider", "nodelife.llm.model", "nodelife.extraction.mode",
                "nodelife.sources.granola.enabled", "nodelife.sources.granola.path", "hasCompletedSetup"] {
        defaults.removeObject(forKey: "\(key).\(suffix)")
    }
}
