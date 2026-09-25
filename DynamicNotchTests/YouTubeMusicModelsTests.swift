import Testing
import Foundation
@testable import DynamicNotch

// MARK: - Helpers

private func websocketMessage(type: String, extra: [String: Any] = [:]) -> Data {
    var dict: [String: Any] = ["type": type]
    dict.merge(extra) { _, new in new }
    return try! JSONSerialization.data(withJSONObject: dict)
}

// MARK: - WebSocketMessage

@Suite("WebSocketMessage parsing")
struct WebSocketMessageTests {

    @Test("Every known message type parses successfully", arguments: [
        "PLAYER_INFO", "VIDEO_CHANGED", "PLAYER_STATE_CHANGED", "POSITION_CHANGED",
        "VOLUME_CHANGED", "REPEAT_CHANGED", "SHUFFLE_CHANGED",
    ])
    func knownTypesParse(rawType: String) {
        let message = WebSocketMessage(from: websocketMessage(type: rawType))
        #expect(message?.type.rawValue == rawType)
    }

    @Test("An unknown type fails to parse")
    func unknownTypeFailsToParse() {
        #expect(WebSocketMessage(from: websocketMessage(type: "NOT_A_REAL_TYPE")) == nil)
    }

    @Test("Malformed JSON fails to parse")
    func malformedJSONFailsToParse() {
        #expect(WebSocketMessage(from: Data("not json".utf8)) == nil)
    }

    @Test("A JSON value with no \"type\" field fails to parse")
    func missingTypeFieldFailsToParse() {
        let data = try! JSONSerialization.data(withJSONObject: ["foo": "bar"])
        #expect(WebSocketMessage(from: data) == nil)
    }

    @Test("extractData() returns the parsed dictionary, including extra fields")
    func extractDataReturnsParsedDictionary() throws {
        let data = websocketMessage(type: "VOLUME_CHANGED", extra: ["volume": 42])
        let message = try #require(WebSocketMessage(from: data))
        let extracted = try #require(message.extractData())
        #expect(extracted["type"] as? String == "VOLUME_CHANGED")
        #expect(extracted["volume"] as? Int == 42)
    }
}

// MARK: - PlaybackResponse.from(websocketData:)

@Suite("PlaybackResponse.from(websocketData:) precedence rules")
struct PlaybackResponseParsingTests {

    @Test("song.isPaused wins over the top-level isPlaying flag")
    func songIsPausedWinsOverTopLevelIsPlaying() {
        let response = PlaybackResponse.from(websocketData: [
            "isPlaying": true,
            "song": ["isPaused": true],
        ])
        #expect(response?.isPaused == true)
    }

    @Test("Without song.isPaused, isPaused is the negation of top-level isPlaying")
    func fallsBackToNegatedTopLevelIsPlaying() {
        let response = PlaybackResponse.from(websocketData: ["isPlaying": true])
        #expect(response?.isPaused == false)
    }

    @Test("With neither field present, isPaused defaults to true")
    func defaultsToPausedWhenNothingIsPresent() {
        let response = PlaybackResponse.from(websocketData: [:])
        #expect(response?.isPaused == true)
    }

    @Test("Title precedence: song.title, then song.alternativeTitle, then top-level title")
    func titlePrecedence() {
        let songTitleWins = PlaybackResponse.from(websocketData: [
            "title": "top-level",
            "song": ["title": "song-title", "alternativeTitle": "alt-title"],
        ])
        #expect(songTitleWins?.title == "song-title")

        let alternativeTitleWins = PlaybackResponse.from(websocketData: [
            "title": "top-level",
            "song": ["alternativeTitle": "alt-title"],
        ])
        #expect(alternativeTitleWins?.title == "alt-title")

        let topLevelTitleWins = PlaybackResponse.from(websocketData: ["title": "top-level"])
        #expect(topLevelTitleWins?.title == "top-level")
    }

    @Test("elapsed comes from song.elapsedSeconds, falling back to top-level position, converting Int to Double")
    func elapsedFallsBackToTopLevelPosition() {
        let fromSong = PlaybackResponse.from(websocketData: ["song": ["elapsedSeconds": 12]])
        #expect(fromSong?.elapsedSeconds == 12.0)

        let fromTopLevel = PlaybackResponse.from(websocketData: ["position": 34])
        #expect(fromTopLevel?.elapsedSeconds == 34.0)

        let songWinsOverTopLevel = PlaybackResponse.from(websocketData: ["position": 34, "song": ["elapsedSeconds": 12]])
        #expect(songWinsOverTopLevel?.elapsedSeconds == 12.0)
    }

    @Test("repeat mapping: NONE/ALL/ONE case-insensitively map to 0/1/2, top-level beats song-level")
    func repeatModeMapping() {
        #expect(PlaybackResponse.from(websocketData: ["repeat": "none"])?.repeatMode == 0)
        #expect(PlaybackResponse.from(websocketData: ["repeat": "ALL"])?.repeatMode == 1)
        #expect(PlaybackResponse.from(websocketData: ["repeat": "One"])?.repeatMode == 2)
        #expect(PlaybackResponse.from(websocketData: ["repeat": "garbage"])?.repeatMode == nil)
        #expect(PlaybackResponse.from(websocketData: [:])?.repeatMode == nil)

        let topLevelWins = PlaybackResponse.from(websocketData: ["repeat": "ALL", "song": ["repeat": "ONE"]])
        #expect(topLevelWins?.repeatMode == 1)

        let songLevelFallback = PlaybackResponse.from(websocketData: ["song": ["repeat": "ONE"]])
        #expect(songLevelFallback?.repeatMode == 2)
    }

    @Test("Top-level shuffle/volume beat song-level isShuffled/volume")
    func topLevelShuffleAndVolumeWin() {
        let shuffle = PlaybackResponse.from(websocketData: ["shuffle": true, "song": ["isShuffled": false]])
        #expect(shuffle?.isShuffled == true)

        let shuffleFallback = PlaybackResponse.from(websocketData: ["song": ["isShuffled": true]])
        #expect(shuffleFallback?.isShuffled == true)

        let volume = PlaybackResponse.from(websocketData: ["volume": 80, "song": ["volume": 10]])
        #expect(volume?.volume == 80.0)

        let volumeFallback = PlaybackResponse.from(websocketData: ["song": ["volume": 10]])
        #expect(volumeFallback?.volume == 10.0)
    }

    @Test("with(elapsedSeconds:) changes only that one field")
    func withElapsedSecondsChangesOnlyThatField() {
        let original = PlaybackResponse.from(websocketData: [
            "title": "Song", "artist": "Artist", "position": 10,
        ])!
        let updated = original.with(elapsedSeconds: 99)
        #expect(updated.elapsedSeconds == 99)
        #expect(updated.title == original.title)
        #expect(updated.artist == original.artist)
        #expect(updated.isPaused == original.isPaused)
    }
}

// MARK: - Decodable conformance

@Suite("PlaybackResponse and AuthResponse decoding")
struct PlaybackResponseDecodingTests {

    @Test("PlaybackResponse decodes with all optional fields missing except the required isPaused")
    func decodesWithOnlyIsPaused() throws {
        let json = Data(#"{"isPaused":true}"#.utf8)
        let response = try JSONDecoder().decode(PlaybackResponse.self, from: json)
        #expect(response.isPaused == true)
        #expect(response.title == nil)
    }

    @Test("PlaybackResponse fails to decode without isPaused")
    func failsToDecodeWithoutIsPaused() {
        let json = Data(#"{"title":"Song"}"#.utf8)
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(PlaybackResponse.self, from: json)
        }
    }

    @Test("AuthResponse decodes accessToken")
    func authResponseDecodesAccessToken() throws {
        let json = Data(#"{"accessToken":"abc123"}"#.utf8)
        let response = try JSONDecoder().decode(AuthResponse.self, from: json)
        #expect(response.accessToken == "abc123")
    }
}
