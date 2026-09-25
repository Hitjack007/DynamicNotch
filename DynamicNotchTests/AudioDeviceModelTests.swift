import Testing
@testable import DynamicNotch

// MARK: - Tests

@Suite("AudioDeviceModel.resolve three-tier priority chain")
struct AudioDeviceModelTests {

    @Test("Priority 1: an exact vendor/product ID match wins regardless of name or CoD")
    func vidPidMatchWins() {
        let model = AudioDeviceModel.resolve(vendorID: 0x004C, productID: 0x2064, cod: 0, name: "Generic Bluetooth Device")
        #expect(model == .airPodsPro2USBC)
    }

    @Test("Priority 1 falls through to the next tier for an unrecognized vendor/product ID")
    func unknownVidPidFallsThrough() {
        let model = AudioDeviceModel.resolve(vendorID: 0x1234, productID: 0x5678, cod: 0, name: "AirPods")
        #expect(model == .airPods2, "With no CoD match, the name tier should still run")
    }

    @Test("Priority 2: class-of-device minor class picks a generic form factor")
    func classOfDeviceFormFactor() {
        let inEarCoD: UInt32 = (0x04 << 8) | (0x01 << 2)
        #expect(AudioDeviceModel.resolve(vendorID: 0, productID: 0, cod: inEarCoD, name: "Unknown") == .genericInEar)

        let overEarCoD: UInt32 = (0x04 << 8) | (0x06 << 2)
        #expect(AudioDeviceModel.resolve(vendorID: 0, productID: 0, cod: overEarCoD, name: "Unknown") == .genericOverEar)

        let otherAudioCoD: UInt32 = (0x04 << 8) | (0x03 << 2)
        #expect(AudioDeviceModel.resolve(vendorID: 0, productID: 0, cod: otherAudioCoD, name: "Unknown") == .genericAudio)
    }

    @Test("A CoD major class other than Audio/Video (0x04) is ignored, falling through to name matching")
    func nonAudioMajorClassFallsThrough() {
        let nonAudioCoD: UInt32 = (0x05 << 8) | (0x01 << 2)
        let model = AudioDeviceModel.resolve(vendorID: 0, productID: 0, cod: nonAudioCoD, name: "AirPods Pro")
        #expect(model == .airPodsPro1)
    }

    @Test("Priority 3: name substrings resolve Apple and Beats devices", arguments: [
        ("AirPods Max", AudioDeviceModel.airPodsMaxLightning),
        ("AirPods Pro", .airPodsPro1),
        ("AirPods", .airPods2),
        ("Beats Solo", .beatsSolo3),
        ("Beats Studio", .beatsStudio3),
        ("Beats Studio Buds", .beatsStudioBuds),
    ])
    func nameSubstringMatching(name: String, expected: AudioDeviceModel) {
        #expect(AudioDeviceModel.resolve(vendorID: 0, productID: 0, cod: 0, name: name) == expected)
    }

    @Test("Generic headphone/earbud name substrings resolve to the right form factor")
    func genericNameSubstrings() {
        #expect(AudioDeviceModel.resolve(vendorID: 0, productID: 0, cod: 0, name: "Some Over-Ear Headphone") == .genericOverEar)
        #expect(AudioDeviceModel.resolve(vendorID: 0, productID: 0, cod: 0, name: "Generic Earbud") == .genericInEar)
        #expect(AudioDeviceModel.resolve(vendorID: 0, productID: 0, cod: 0, name: "Mystery Speaker") == .genericAudio)
    }

    @Test("Every model has a non-empty SF Symbol name")
    func everyModelHasAnSFSymbolName() {
        let allModels: [AudioDeviceModel] = [
            .airPods1, .airPods2, .airPods3, .airPodsPro1, .airPodsPro2Lightning, .airPodsPro2USBC,
            .airPodsMaxLightning, .airPodsMaxUSBC, .beatsStudioBuds, .beatsFitPro, .beatsStudioBudsPlus,
            .beatsFlex, .beatsSolo3, .beatsStudio3, .beatsPowerBeatsPro,
            .genericInEar, .genericOverEar, .genericAudio,
        ]
        for model in allModels {
            #expect(!model.sfSymbolName.isEmpty, "\(model) has no SF Symbol name")
        }
    }
}
