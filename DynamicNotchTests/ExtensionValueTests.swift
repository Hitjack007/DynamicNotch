import Testing
import Foundation
@testable import DynamicNotch

// MARK: - Tests

@Suite("ExtensionValue coding and conversions")
struct ExtensionValueTests {

    @Test("Every case round-trips through JSON, except .double(3.0), which decodes back as .int(3)")
    func codableRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for value: ExtensionValue in [.string("hello"), .int(42), .bool(true), .bool(false), .null] {
            let data = try encoder.encode(value)
            #expect(try decoder.decode(ExtensionValue.self, from: data) == value)
        }

        // A whole-number Double is indistinguishable from an Int once it hits the wire —
        // JSONDecoder tries Bool, then Int, then Double, in that order, and Int succeeds first.
        let wholeNumber = try encoder.encode(ExtensionValue.double(3.0))
        #expect(try decoder.decode(ExtensionValue.self, from: wholeNumber) == .int(3))

        let fractional = try encoder.encode(ExtensionValue.double(3.5))
        #expect(try decoder.decode(ExtensionValue.self, from: fractional) == .double(3.5))
    }

    @Test("Decoding an array or object throws instead of silently producing a value")
    func decodingCompoundJSONThrows() {
        let decoder = JSONDecoder()
        #expect(throws: (any Error).self) {
            _ = try decoder.decode(ExtensionValue.self, from: Data("[1,2,3]".utf8))
        }
        #expect(throws: (any Error).self) {
            _ = try decoder.decode(ExtensionValue.self, from: Data(#"{"a":1}"#.utf8))
        }
    }

    @Test("stringValue converts every non-null case, and returns nil only for .null")
    func stringValueConversions() {
        #expect(ExtensionValue.string("hi").stringValue == "hi")
        #expect(ExtensionValue.int(7).stringValue == "7")
        #expect(ExtensionValue.double(3.0).stringValue == "3.0")
        #expect(ExtensionValue.bool(true).stringValue == "true")
        #expect(ExtensionValue.null.stringValue == nil)
    }

    @Test("doubleValue parses numeric strings but rejects bool and null")
    func doubleValueConversions() {
        #expect(ExtensionValue.double(1.5).doubleValue == 1.5)
        #expect(ExtensionValue.int(2).doubleValue == 2.0)
        #expect(ExtensionValue.string("3.25").doubleValue == 3.25)
        #expect(ExtensionValue.string("not-a-number").doubleValue == nil)
        #expect(ExtensionValue.bool(true).doubleValue == nil)
        #expect(ExtensionValue.null.doubleValue == nil)
    }

    @Test("intValue truncates doubles and rejects bool and null")
    func intValueConversions() {
        #expect(ExtensionValue.int(5).intValue == 5)
        #expect(ExtensionValue.double(5.9).intValue == 5)
        #expect(ExtensionValue.string("10").intValue == 10)
        #expect(ExtensionValue.string("not-a-number").intValue == nil)
        #expect(ExtensionValue.bool(true).intValue == nil)
        #expect(ExtensionValue.null.intValue == nil)
    }

    @Test("boolValue parses \"true\"/\"false\" strings but rejects numbers and null")
    func boolValueConversions() {
        #expect(ExtensionValue.bool(true).boolValue == true)
        #expect(ExtensionValue.string("true").boolValue == true)
        #expect(ExtensionValue.string("false").boolValue == false)
        #expect(ExtensionValue.string("nope").boolValue == nil)
        #expect(ExtensionValue.int(1).boolValue == nil)
        #expect(ExtensionValue.double(1).boolValue == nil)
        #expect(ExtensionValue.null.boolValue == nil)
    }
}
