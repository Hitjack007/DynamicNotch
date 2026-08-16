//
//  SafariCookieReader.swift
//  boringNotch
//
//  Parses Safari's BinaryCookies format to extract the claude.ai session key
//  without requiring any user interaction.
//
//  Format reference (all integers little-endian unless noted):
//    File header: "cook" magic + BE uint32 page count + BE uint32 page sizes[]
//    Page header: LE uint32 cookie count + LE uint32 cookie offsets[]
//    Cookie record at each offset:
//      +0  size (4), +4 unknown (4), +8 flags (4), +12 unknown (4)
//      +16 domain offset (4), +20 name offset (4)
//      +24 path offset (4), +28 value offset (4)
//      +32 unknown (8), +40 expiry (Double), +48 creation (Double)
//      +56 null-terminated strings at the offsets above
//

import Foundation

struct SafariCookieReader {
    static func findClaudeSessionKey() -> String? {
        findCookie(named: "sessionKey")
    }

    static func findCookie(named cookieName: String) -> String? {
        // Safari is sandboxed; its cookie store lives in the container on modern macOS.
        // Try the container path first, then fall back to the legacy location.
        let home = NSHomeDirectory()
        let candidates = [
            home + "/Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies",
            home + "/Library/Cookies/Cookies.binarycookies",
        ]
        for path in candidates {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { continue }
            if let result = parseFile(data, cookieName: cookieName) { return result }
        }
        return nil
    }

    // MARK: - File

    private static func parseFile(_ data: Data, cookieName: String) -> String? {
        guard data.count >= 8,
              String(bytes: data[0..<4], encoding: .ascii) == "cook" else { return nil }

        let pageCount = Int(be32(data, 4))
        var cursor = 8

        var sizes: [Int] = []
        for _ in 0..<pageCount {
            guard cursor + 4 <= data.count else { return nil }
            sizes.append(Int(be32(data, cursor)))
            cursor += 4
        }

        for size in sizes {
            guard cursor + size <= data.count else { break }
            if let found = parsePage(Data(data[cursor..<(cursor + size)]), cookieName: cookieName) { return found }
            cursor += size
        }
        return nil
    }

    // MARK: - Page

    private static func parsePage(_ page: Data, cookieName: String) -> String? {
        guard page.count >= 8 else { return nil }
        let count = Int(le32(page, 4))
        for i in 0..<count {
            let idx = 8 + i * 4
            guard idx + 4 <= page.count else { break }
            let offset = Int(le32(page, idx))
            if let found = parseCookie(page, at: offset, cookieName: cookieName) { return found }
        }
        return nil
    }

    // MARK: - Cookie record

    private static func parseCookie(_ page: Data, at base: Int, cookieName: String) -> String? {
        guard base + 56 <= page.count else { return nil }

        let domainOff = Int(le32(page, base + 16))
        let nameOff   = Int(le32(page, base + 20))
        let valueOff  = Int(le32(page, base + 28))

        guard let domain = cstr(page, base + domainOff), domain.contains("claude.ai") else { return nil }
        guard let name   = cstr(page, base + nameOff),   name == cookieName             else { return nil }
        return cstr(page, base + valueOff)
    }

    // MARK: - Helpers

    private static func cstr(_ data: Data, _ start: Int) -> String? {
        guard start >= 0, start < data.count else { return nil }
        var end = start
        while end < data.count && data[end] != 0 { end += 1 }
        return String(bytes: data[start..<end], encoding: .utf8)
    }

    private static func le32(_ data: Data, _ offset: Int) -> UInt32 {
        data[offset..<(offset + 4)].withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
    }

    private static func be32(_ data: Data, _ offset: Int) -> UInt32 {
        data[offset..<(offset + 4)].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
    }
}
