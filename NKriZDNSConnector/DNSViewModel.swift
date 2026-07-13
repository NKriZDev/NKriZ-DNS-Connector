import Foundation

@MainActor
final class DNSViewModel: ObservableObject {
    @Published private(set) var activeMode: DNSMode?
    @Published private(set) var statusMessage = "Checking DNS…"
    @Published private(set) var isApplying = false
    @Published private(set) var isRefreshingIP = false
    @Published private(set) var ipRefreshOutput: String?
    @Published var lastError: String?

    private let manager = DNSManager.shared
    private let ddnsClient = DDNSClient.shared

    var menuBarSymbol: String {
        switch activeMode {
        case .custom: return "network.badge.shield.half.filled"
        case .automatic: return "network"
        case nil: return "network.slash"
        }
    }

    init() {
        refreshStatus()
    }

    func refreshStatus() {
        let services = manager.listEnabledNetworkServices()
        guard !services.isEmpty else {
            activeMode = nil
            statusMessage = "No network services found"
            return
        }

        let modes = services.compactMap { manager.currentMode(for: $0) }
        if modes.allSatisfy({ $0 == .automatic }) {
            activeMode = .automatic
            statusMessage = "Using automatic DNS on \(services.joined(separator: ", "))"
        } else if modes.allSatisfy({ $0 == .custom }) {
            activeMode = .custom
            statusMessage = "Using NKriZ DNS on \(services.joined(separator: ", "))"
        } else {
            activeMode = nil
            statusMessage = "Mixed DNS settings across interfaces"
        }
    }

    func apply(mode: DNSMode) {
        guard !isApplying else { return }

        isApplying = true
        lastError = nil
        statusMessage = "Applying \(mode.label)…"

        Task {
            do {
                try await manager.apply(mode: mode)
                activeMode = mode
                statusMessage = mode == .custom
                    ? "NKriZ DNS active (\(DNSConfiguration.primaryDNS), \(DNSConfiguration.secondaryDNS))"
                    : "Automatic DNS active"
            } catch {
                lastError = error.localizedDescription
                statusMessage = "Failed to update DNS"
                refreshStatus()
            }

            isApplying = false
        }
    }

    func refreshIP() {
        guard !isRefreshingIP else { return }

        isRefreshingIP = true
        ipRefreshOutput = "Refreshing…"

        Task {
            do {
                let output = try await ddnsClient.refreshIP()
                ipRefreshOutput = output
            } catch {
                ipRefreshOutput = "Error: \(error.localizedDescription)"
            }

            isRefreshingIP = false
        }
    }

    var ipRefreshOutputIsIP: Bool {
        guard let ipRefreshOutput else { return false }
        return DDNSClient.isIPAddress(ipRefreshOutput)
    }
}
