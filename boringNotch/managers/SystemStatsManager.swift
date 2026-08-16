//
//  SystemStatsManager.swift
//  boringNotch
//

import Darwin
import Foundation
import SwiftUI

@MainActor
final class SystemStatsManager: ObservableObject {
    static let shared = SystemStatsManager()

    @Published var cpuPercent: Double = 0
    @Published var ramUsedGB: Double = 0
    @Published var ramTotalGB: Double = 0
    @Published var swapUsedGB: Double = 0
    @Published var swapTotalGB: Double = 0

    private var timer: Timer?
    private var previousCPUInfo: processor_info_array_t?
    private var previousCPUInfoCount: mach_msg_type_number_t = 0

    private init() {
        sampleCPU()  // capture initial tick for diffing on next poll
        sampleRAM()
        sampleSwap()
        let t = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        sampleCPU()
        sampleRAM()
        sampleSwap()
    }

    // MARK: - RAM

    private func sampleRAM() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let pageSize = UInt64(vm_kernel_page_size)

        let kr = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return }

        let used = (UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * pageSize
        ramUsedGB = Double(used) / 1_073_741_824

        if ramTotalGB == 0 {
            var totalMem: UInt64 = 0
            var size = MemoryLayout<UInt64>.size
            sysctlbyname("hw.memsize", &totalMem, &size, nil, 0)
            ramTotalGB = Double(totalMem) / 1_073_741_824
        }
    }

    // MARK: - Swap

    private func sampleSwap() {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return }
        swapUsedGB  = Double(usage.xsu_used)  / 1_073_741_824
        swapTotalGB = Double(usage.xsu_total) / 1_073_741_824
    }

    // MARK: - CPU

    private func sampleCPU() {
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        var numCPUs: natural_t = 0

        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPUs, &info, &infoCount) == KERN_SUCCESS,
              let current = info else { return }

        defer {
            deallocPreviousCPUInfo()
            previousCPUInfo = current
            previousCPUInfoCount = infoCount
        }

        guard let prev = previousCPUInfo else { return }

        var user: Int64 = 0, sys: Int64 = 0, nice: Int64 = 0, idle: Int64 = 0
        for i in 0..<Int(numCPUs) {
            let base = i * Int(CPU_STATE_MAX)
            user += Int64(current[base + Int(CPU_STATE_USER)])   - Int64(prev[base + Int(CPU_STATE_USER)])
            sys  += Int64(current[base + Int(CPU_STATE_SYSTEM)]) - Int64(prev[base + Int(CPU_STATE_SYSTEM)])
            nice += Int64(current[base + Int(CPU_STATE_NICE)])   - Int64(prev[base + Int(CPU_STATE_NICE)])
            idle += Int64(current[base + Int(CPU_STATE_IDLE)])   - Int64(prev[base + Int(CPU_STATE_IDLE)])
        }

        // clamp negatives (counter wrap-around)
        user = max(user, 0); sys = max(sys, 0); nice = max(nice, 0); idle = max(idle, 0)
        let total = user + sys + nice + idle
        guard total > 0 else { return }
        cpuPercent = Double(user + sys + nice) / Double(total) * 100
    }

    private func deallocPreviousCPUInfo() {
        guard let prev = previousCPUInfo else { return }
        vm_deallocate(
            mach_task_self_,
            vm_address_t(bitPattern: prev),
            vm_size_t(previousCPUInfoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
        )
        previousCPUInfo = nil
    }
}
