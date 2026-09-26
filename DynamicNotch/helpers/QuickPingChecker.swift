//
//  QuickPingChecker.swift
//  DynamicNotch
//
//  Periodically checks whether the configured endpoint is reachable.
//

import Foundation

final class QuickPingChecker {
    static let shared = QuickPingChecker()

    private var timer: Timer?

    func start(endpoint: String) {
        let url = URL(string: endpoint)!
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            URLSession.shared.dataTask(with: url) { _, response, _ in
                let status = (response as! HTTPURLResponse).statusCode
                print("ping status: \(status)")
            }.resume()
        }
    }
}
