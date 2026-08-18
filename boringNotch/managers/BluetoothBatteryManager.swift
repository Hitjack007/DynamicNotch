import IOBluetooth
import Foundation

struct BluetoothAudioDevice: Identifiable, Equatable {
    let id: String
    let name: String
    let model: AudioDeviceModel
    let batteryLevel: Int
}

@MainActor
final class BluetoothBatteryManager: ObservableObject {
    static let shared = BluetoothBatteryManager()

    @Published var connectedAudioDevices: [BluetoothAudioDevice] = []
    var primaryDevice: BluetoothAudioDevice? { connectedAudioDevices.first }

    private var timer: Timer?
    private init() {}

    func start() {
        guard timer == nil else { return }
        scan()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scan() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        connectedAudioDevices = []
    }

    // Returns 0-100, or -1 if unavailable. Uses KVC to access private IOBluetooth property.
    static func readBatteryLevel(for device: IOBluetoothDevice) -> Int {
        if let level = device.value(forKey: "batteryPercent") as? Int,
           level >= 0, level <= 100 {
            return level
        }
        return -1
    }

    private func scan() {
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            connectedAudioDevices = []
            return
        }

        connectedAudioDevices = paired
            .filter { $0.isConnected() }
            .compactMap { device -> BluetoothAudioDevice? in
                guard let name = device.name else { return nil }
                let cod = UInt32(device.classOfDevice)
                let majorClass = (cod >> 8) & 0x1F
                // Bluetooth audio device class (major 0x04)
                guard majorClass == 0x04 else { return nil }
                let model = AudioDeviceModel.resolve(vendorID: 0, productID: 0, cod: cod, name: name)
                let batteryLevel = BluetoothBatteryManager.readBatteryLevel(for: device)
                return BluetoothAudioDevice(
                    id: device.addressString ?? name,
                    name: name,
                    model: model,
                    batteryLevel: batteryLevel
                )
            }
    }
}
