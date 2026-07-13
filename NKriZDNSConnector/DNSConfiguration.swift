import Foundation

enum DNSMode: String, CaseIterable {
    case automatic
    case custom

    var label: String {
        switch self {
        case .automatic: return "Automatic (DHCP)"
        case .custom: return "NKriZ DNS"
        }
    }
}

enum DNSConfiguration {
    static let primaryDNS = "178.22.122.101"
    static let secondaryDNS = "185.51.200.1"
    static let ddnsUpdateURL = URL(string: "https://ddns.shecan.ir/update?password=c591cb80e0d326bc")!

    static var customServers: [String] {
        [primaryDNS, secondaryDNS]
    }
}
