import Testing
import Foundation
@testable import DynamicNotch

// MARK: - WebSocketURLBuilder

@Suite("WebSocketURLBuilder.buildURL")
struct WebSocketURLBuilderTests {

    @Test("http maps to ws, https maps to wss")
    func schemeMapping() {
        #expect(WebSocketURLBuilder.buildURL(from: "http://localhost:26538", token: "t")?.scheme == "ws")
        #expect(WebSocketURLBuilder.buildURL(from: "https://localhost:26538", token: "t")?.scheme == "wss")
    }

    @Test("Any other scheme is left unchanged")
    func otherSchemesAreUnchanged() {
        #expect(WebSocketURLBuilder.buildURL(from: "ws://localhost:26538", token: "t")?.scheme == "ws")
    }

    @Test("The path is always replaced with /api/v1/ws, overwriting any existing path")
    func pathIsAlwaysReplaced() {
        let url = WebSocketURLBuilder.buildURL(from: "http://localhost:26538/some/old/path", token: "t")
        #expect(url?.path == "/api/v1/ws")
    }

    @Test("The token is percent-encoded into the query, overwriting any existing query")
    func tokenIsEncodedIntoQuery() {
        let url = WebSocketURLBuilder.buildURL(from: "http://localhost:26538?old=query", token: "a b&c")
        let components = URLComponents(url: url!, resolvingAgainstBaseURL: false)
        #expect(components?.queryItems == [URLQueryItem(name: "token", value: "a b&c")])
        #expect(url?.query?.contains("old") == false)
    }

    @Test("An unparseable base URL returns nil")
    func unparseableBaseURLReturnsNil() {
        #expect(WebSocketURLBuilder.buildURL(from: "http://%", token: "t") == nil)
    }
}

// MARK: - YouTubeMusicError

@Suite("YouTubeMusicError.errorDescription")
struct YouTubeMusicErrorTests {

    @Test("Every case has the expected description")
    func everyCaseHasExpectedDescription() {
        #expect(YouTubeMusicError.invalidURL.errorDescription == "Invalid URL")
        #expect(YouTubeMusicError.invalidResponse.errorDescription == "Invalid response")
        #expect(YouTubeMusicError.httpError(404).errorDescription == "HTTP error: 404")
        #expect(YouTubeMusicError.authenticationRequired.errorDescription == "Authentication required")
        #expect(YouTubeMusicError.webSocketNotConnected.errorDescription == "WebSocket not connected")
        #expect(YouTubeMusicError.encodingFailed.errorDescription == "Failed to encode data")
        #expect(YouTubeMusicError.decodingFailed.errorDescription == "Failed to decode data")
    }
}

// MARK: - AuthenticationState

@Suite("AuthenticationState")
struct AuthenticationStateTests {

    private struct DummyError: Error {}

    @Test("isAuthenticated and token are only non-trivial for .authenticated")
    func onlyAuthenticatedCaseCarriesAToken() {
        #expect(AuthenticationState.unauthenticated.isAuthenticated == false)
        #expect(AuthenticationState.unauthenticated.token == nil)

        #expect(AuthenticationState.authenticating.isAuthenticated == false)
        #expect(AuthenticationState.authenticating.token == nil)

        #expect(AuthenticationState.authenticated("tok").isAuthenticated == true)
        #expect(AuthenticationState.authenticated("tok").token == "tok")

        #expect(AuthenticationState.failed(DummyError()).isAuthenticated == false)
        #expect(AuthenticationState.failed(DummyError()).token == nil)
    }
}
