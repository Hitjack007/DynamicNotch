import Testing
import Foundation
@testable import DynamicNotch

// MARK: - NowPlayingUpdate / NowPlayingPayload decoding

@Suite("NowPlayingUpdate and NowPlayingPayload decoding")
struct NowPlayingPayloadDecodingTests {

    @Test("Every payload field is optional")
    func everyPayloadFieldIsOptional() throws {
        let json = Data(#"{"payload":{}}"#.utf8)
        let update = try JSONDecoder().decode(NowPlayingUpdate.self, from: json)
        #expect(update.payload.title == nil)
        #expect(update.diff == nil)
    }

    @Test("A full payload round-trips through encode/decode")
    func fullPayloadRoundTrips() throws {
        let payload = NowPlayingPayload(
            title: "Song", artist: "Artist", album: "Album", duration: 180,
            elapsedTime: 30, shuffleMode: 1, repeatMode: 2, artworkData: "base64",
            timestamp: "2026-01-01T00:00:00Z", playbackRate: 1.0, playing: true,
            parentApplicationBundleIdentifier: "com.apple.Music",
            bundleIdentifier: "com.apple.Music", volume: 0.5
        )
        let update = NowPlayingUpdate(payload: payload, diff: true)

        let data = try JSONEncoder().encode(update)
        let restored = try JSONDecoder().decode(NowPlayingUpdate.self, from: data)

        #expect(restored.payload.title == "Song")
        #expect(restored.payload.artist == "Artist")
        #expect(restored.diff == true)
        #expect(restored.payload.duration == 180)
    }

    @Test("A missing \"payload\" key fails to decode")
    func missingPayloadKeyThrows() {
        let json = Data(#"{"diff":true}"#.utf8)
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(NowPlayingUpdate.self, from: json)
        }
    }
}

// MARK: - JSONLinesPipeHandler

private struct Line: Decodable, Equatable {
    let a: Int
}

/// Writes `text` to the handler's pipe and closes the writer, then collects every
/// successfully decoded line. Always closes the writer first — readData() blocks on
/// the pipe's readabilityHandler, and an unclosed writer with no more data would hang.
private func collectLines(from text: String) async -> [Line] {
    let handler = JSONLinesPipeHandler()
    let pipe = await handler.getPipe()

    let writer = pipe.fileHandleForWriting
    writer.write(Data(text.utf8))
    try? writer.close()

    var collected: [Line] = []
    await handler.readJSONLines(as: Line.self) { line in
        collected.append(line)
    }
    return collected
}

@Suite("JSONLinesPipeHandler line splitting")
struct JSONLinesPipeHandlerTests {

    @Test("Complete lines are decoded in order", .timeLimit(.minutes(1)))
    func completeLinesAreDecodedInOrder() async {
        let lines = await collectLines(from: "{\"a\":1}\n{\"a\":2}\n")
        #expect(lines == [Line(a: 1), Line(a: 2)])
    }

    @Test("Empty lines are skipped", .timeLimit(.minutes(1)))
    func emptyLinesAreSkipped() async {
        let lines = await collectLines(from: "\n{\"a\":1}\n\n{\"a\":2}\n")
        #expect(lines == [Line(a: 1), Line(a: 2)])
    }

    @Test("A line that fails to decode is silently dropped, not fatal to the rest", .timeLimit(.minutes(1)))
    func undecodableLinesAreDropped() async {
        let lines = await collectLines(from: "not-json\n{\"a\":5}\n{\"missing\":\"a\"}\n{\"a\":6}\n")
        #expect(lines == [Line(a: 5), Line(a: 6)])
    }

    @Test("A trailing line with no newline is never delivered", .timeLimit(.minutes(1)))
    func partialTrailingLineIsNeverDelivered() async {
        let lines = await collectLines(from: "{\"a\":1}\n{\"a\":9}")
        #expect(lines == [Line(a: 1)], "The partial second line has no closing newline and should stay buffered forever, not be delivered")
    }
}
