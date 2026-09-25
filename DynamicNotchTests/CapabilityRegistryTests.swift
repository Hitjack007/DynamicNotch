import Testing
@testable import DynamicNotch

// MARK: - Tests

@Suite("CapabilityRegistry completeness and consistency")
struct CapabilityRegistryTests {

    @Test("Every TriggerID case has exactly one descriptor")
    func everyTriggerHasExactlyOneDescriptor() {
        for id in TriggerID.allCases {
            let matches = CapabilityRegistry.triggers.filter { $0.id == id }
            #expect(matches.count == 1, "\(id.rawValue) should have exactly one TriggerDescriptor, found \(matches.count)")
        }
        #expect(CapabilityRegistry.triggers.count == TriggerID.allCases.count, "There should be no descriptor for a trigger id that no longer exists")
    }

    @Test("Every ActionID case has exactly one descriptor")
    func everyActionHasExactlyOneDescriptor() {
        for id in ActionID.allCases {
            let matches = CapabilityRegistry.actions.filter { $0.id == id }
            #expect(matches.count == 1, "\(id.rawValue) should have exactly one ActionDescriptor, found \(matches.count)")
        }
        #expect(CapabilityRegistry.actions.count == ActionID.allCases.count, "There should be no descriptor for an action id that no longer exists")
    }

    @Test("trigger(_:) and action(_:) never force-unwrap-crash for any known id")
    func lookupsNeverCrash() {
        for id in TriggerID.allCases {
            #expect(CapabilityRegistry.trigger(id).id == id)
        }
        for id in ActionID.allCases {
            #expect(CapabilityRegistry.action(id).id == id)
        }
    }

    @Test("prerequisiteEligible agrees with the six ids ExtensionActionExecutor.currentlyMatches hard-codes as non-eligible")
    func prerequisiteEligibilityMatchesExecutorSwitch() {
        let nonEligibleInExecutor: Set<ActionID> = [
            .notificationRequest, .notificationShowInApp, .sneakPeekShow,
            .mediaNextTrack, .mediaPreviousTrack, .shortcutRun,
        ]
        for descriptor in CapabilityRegistry.actions {
            let isEligible = descriptor.prerequisiteEligible
            let executorConsidersEligible = !nonEligibleInExecutor.contains(descriptor.id)
            #expect(isEligible == executorConsidersEligible, "\(descriptor.id.rawValue): CapabilityRegistry says prerequisiteEligible=\(isEligible), but ExtensionActionExecutor.currentlyMatches disagrees")
        }
    }

    @Test("referenceText() mentions every trigger and action id, with the prerequisite suffix only on eligible actions")
    func referenceTextIsComplete() {
        let text = CapabilityRegistry.referenceText()

        for descriptor in CapabilityRegistry.triggers {
            #expect(text.contains(descriptor.id.rawValue))
        }
        for descriptor in CapabilityRegistry.actions {
            #expect(text.contains(descriptor.id.rawValue))
            let line = text.split(separator: "\n").first { $0.contains("- \(descriptor.id.rawValue):") }
            #expect(line != nil)
            if let line {
                #expect(line.contains("(usable as a prerequisite)") == descriptor.prerequisiteEligible, "\(descriptor.id.rawValue) prerequisite suffix should track prerequisiteEligible")
            }
        }
    }

    @Test("chatbotPrompt embeds the request text and the caller's current rules JSON verbatim")
    func chatbotPromptEmbedsInputs() {
        let prompt = CapabilityRegistry.chatbotPrompt(currentRulesJSON: "[{\"marker\":\"unique-rules-json\"}]", request: "turn on Do Not Disturb at night")
        #expect(prompt.contains("turn on Do Not Disturb at night"))
        #expect(prompt.contains("unique-rules-json"))
    }
}
