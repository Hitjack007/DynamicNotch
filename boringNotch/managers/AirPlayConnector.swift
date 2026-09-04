import CoreAudio
import Foundation
import Network

// Wakes a dormant AirPlay device via RTSP handshake, then waits for CoreAudio
// to register it so the caller can set it as the default output.
@MainActor
final class AirPlayConnector: ObservableObject {
    static let shared = AirPlayConnector()

    @Published var connectingDevices: Set<String> = []

    private enum Err: Error { case connectionFailed, timeout }

    private init() {}

    func connect(to device: DormantAirPlayDevice) async {
        guard !connectingDevices.contains(device.id) else { return }
        connectingDevices.insert(device.id)
        defer { connectingDevices.remove(device.id) }

        do {
            try await sendRTSPOptions(to: device.endpoint)
            let deviceID = try await waitForCoreAudioDevice(named: device.name, timeout: 8)
            AudioOutputManager.shared.setDefault(deviceID)
        } catch {
            // silent failure — device stays greyed out, user can retry
        }
    }

    // MARK: - Private

    private func sendRTSPOptions(to endpoint: NWEndpoint) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let conn = NWConnection(to: endpoint, using: .tcp)
            var settled = false

            let settle: (Error?) -> Void = { err in
                guard !settled else { return }
                settled = true
                conn.cancel()
                if let e = err { cont.resume(throwing: e) } else { cont.resume() }
            }

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let req = "OPTIONS * RTSP/1.0\r\nCSeq: 1\r\nUser-Agent: DynamicNotch\r\n\r\n"
                    conn.send(content: Data(req.utf8), completion: .contentProcessed { _ in })
                    conn.receive(minimumIncompleteLength: 1, maximumLength: 256) { _, _, _, _ in
                        settle(nil)
                    }
                case .failed:
                    settle(Err.connectionFailed)
                default:
                    break
                }
            }
            conn.start(queue: .main)
        }
    }

    // Polls CoreAudio until a device with the given name appears (HomePod registered by OS)
    private func waitForCoreAudioDevice(named name: String, timeout: TimeInterval) async throws -> AudioDeviceID {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            AudioOutputManager.shared.refresh()
            if let match = AudioOutputManager.shared.outputDevices.first(where: {
                $0.name.lowercased() == name.lowercased()
            }) {
                return match.id
            }
            try await Task.sleep(for: .milliseconds(500))
        }
        throw Err.timeout
    }
}
