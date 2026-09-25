import Testing
@testable import DynamicNotch

// MARK: - Tests

@Suite("SMC key formatting and byte conversion")
struct SMCKeysTests {

    @Test("Templated fan keys are formatted with the zero-based fan index")
    func fanKeyFormatting() {
        #expect(SMCFanKey.key(SMCFanKey.target, fan: 1) == "F1Tg")
        #expect(SMCFanKey.key(SMCFanKey.actual, fan: 0) == "F0Ac")
        #expect(SMCFanKey.key(SMCFanKey.minimum, fan: 2) == "F2Mn")
        #expect(SMCFanKey.key(SMCFanKey.maximum, fan: 3) == "F3Mx")
    }

    @Test("Float <-> SMC bytes round-trips, including the all-zero auto value")
    func floatByteRoundTrip() {
        let bytes = floatToSMCBytes(1234.5)
        #expect(bytes.count == 4)
        #expect(smcBytesToFloat(bytes, size: 4) == 1234.5)

        // This is the exact value ThermalManager.resetToAuto() writes to hand fans back to Apple.
        #expect(floatToSMCBytes(0) == [0, 0, 0, 0])
    }

    @Test("smcBytesToFloat guards against short input")
    func smcBytesToFloatGuards() {
        #expect(smcBytesToFloat([0x00, 0x00, 0x80, 0x3F], size: 3) == 0, "size < 4 must be rejected even with enough bytes")
        #expect(smcBytesToFloat([0x00, 0x00, 0x80], size: 4) == 0, "bytes.count < 4 must be rejected even with a claimed size of 4")
    }

    @Test("ioftBytesToFloat decodes 16.16 fixed point from the first 4 bytes, little-endian")
    func ioftFixedPointDecoding() {
        // integer = 0x2D (45), fraction = 0x8000 / 65536 = 0.5
        #expect(ioftBytesToFloat([0x00, 0x80, 0x2D, 0x00]) == 45.5)
        #expect(ioftBytesToFloat([0x00, 0x00, 0x00, 0x00]) == 0)
    }

    @Test("ioftBytesToFloat guards against short input")
    func ioftBytesToFloatGuards() {
        #expect(ioftBytesToFloat([0x00, 0x80, 0x2D]) == 0)
    }

    @Test("SMC command opcodes are pinned to the values IOKit expects")
    func smcCommandRawValues() {
        #expect(SMCCommand.readBytes.rawValue == 5)
        #expect(SMCCommand.writeBytes.rawValue == 6)
        #expect(SMCCommand.getKeyFromIndex.rawValue == 8)
        #expect(SMCCommand.readKeyInfo.rawValue == 9)
    }
}
