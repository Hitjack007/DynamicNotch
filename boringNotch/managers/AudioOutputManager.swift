import CoreAudio
import Foundation
import Network

struct AudioOutputDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let name: String
}

struct DormantAirPlayDevice: Identifiable, Equatable {
    let id: String
    let name: String
}

@MainActor
final class AudioOutputManager: ObservableObject {
    static let shared = AudioOutputManager()

    @Published var outputDevices: [AudioOutputDevice] = []
    @Published var currentDeviceID: AudioDeviceID = 0
    @Published var dormantAirPlayDevices: [DormantAirPlayDevice] = []

    private var raopBrowser: NWBrowser?
    private var airplayBrowser: NWBrowser?
    private var raopNames: Set<String> = []
    private var airplayNames: Set<String> = []

    private init() {
        refresh()
        startBonjourBrowsing()
    }

    func refresh() {
        outputDevices = listOutputDevices()
        currentDeviceID = defaultOutputDeviceID()
        updateDormantDevices()
    }

    func setDefault(_ deviceID: AudioDeviceID) {
        var id = deviceID
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size), &id
        )
        refresh()
    }

    // MARK: - Bonjour Discovery

    private func startBonjourBrowsing() {
        raopBrowser = makeBrowser(type: "_raop._tcp")
        airplayBrowser = makeBrowser(type: "_airplay._tcp")
        raopBrowser?.start(queue: .main)
        airplayBrowser?.start(queue: .main)
    }

    private func makeBrowser(type serviceType: String) -> NWBrowser {
        let descriptor = NWBrowser.Descriptor.bonjourWithTXTRecord(type: serviceType, domain: nil)
        let browser = NWBrowser(for: descriptor, using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor [weak self] in
                self?.handleBrowseResults(results, serviceType: serviceType)
            }
        }
        return browser
    }

    private func handleBrowseResults(_ results: Set<NWBrowser.Result>, serviceType: String) {
        var names: Set<String> = []
        for result in results {
            guard case let .service(name: svcName, type: _, domain: _, interface: _) = result.endpoint else { continue }
            let displayName: String
            // _raop._tcp service names are "MACADDR@DeviceName" — strip the MAC prefix
            if serviceType == "_raop._tcp", let atRange = svcName.range(of: "@") {
                displayName = String(svcName[atRange.upperBound...])
            } else {
                displayName = svcName
            }
            guard !displayName.isEmpty else { continue }
            names.insert(displayName)
        }
        if serviceType == "_raop._tcp" {
            raopNames = names
        } else {
            airplayNames = names
        }
        updateDormantDevices()
    }

    private func updateDormantDevices() {
        let allBonjour = airplayNames.union(raopNames)
        let activeNames = Set(outputDevices.map { $0.name.lowercased() })
        dormantAirPlayDevices = allBonjour
            .filter { !activeNames.contains($0.lowercased()) }
            .sorted()
            .map { DormantAirPlayDevice(id: $0, name: $0) }
    }

    // MARK: - Private

    private func listOutputDevices() -> [AudioOutputDevice] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size
        ) == noErr else { return [] }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids
        ) == noErr else { return [] }

        return ids.compactMap { id -> AudioOutputDevice? in
            let transport = transportType(id)
            guard isPhysicalTransport(id), let name = deviceName(id) else { return nil }
            if transport != kAudioDeviceTransportTypeAirPlay {
                guard isOutputDevice(id) else { return nil }
            }
            return AudioOutputDevice(id: id, name: name)
        }
    }

    private func isOutputDevice(_ id: AudioDeviceID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr && size > 0
    }

    private func transportType(_ id: AudioDeviceID) -> UInt32 {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &transport)
        return transport
    }

    private func isPhysicalTransport(_ id: AudioDeviceID) -> Bool {
        switch transportType(id) {
        case kAudioDeviceTransportTypeBuiltIn,
             kAudioDeviceTransportTypeUSB,
             kAudioDeviceTransportTypeFireWire,
             kAudioDeviceTransportTypeBluetooth,
             kAudioDeviceTransportTypeBluetoothLE,
             kAudioDeviceTransportTypeHDMI,
             kAudioDeviceTransportTypeDisplayPort,
             kAudioDeviceTransportTypeAirPlay,
             kAudioDeviceTransportTypeThunderbolt:
            return true
        default:
            return false
        }
    }

    private func deviceName(_ id: AudioDeviceID) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &name) == noErr else { return nil }
        return name as String
    }

    private func defaultOutputDeviceID() -> AudioDeviceID {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id
        )
        return id
    }
}
