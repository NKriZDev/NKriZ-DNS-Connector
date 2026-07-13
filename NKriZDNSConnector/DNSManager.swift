import AppKit
import Foundation

enum DNSManagerError: LocalizedError {
    case noNetworkServices
    case commandFailed(String)
    case authorizationCancelled

    var errorDescription: String? {
        switch self {
        case .noNetworkServices:
            return "No active network services found."
        case .commandFailed(let message):
            return message
        case .authorizationCancelled:
            return "Administrator authorization was cancelled."
        }
    }
}

final class DNSManager {
    static let shared = DNSManager()

    private let networkSetupPath = "/usr/sbin/networksetup"

    private init() {}

    func listEnabledNetworkServices() -> [String] {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: networkSetupPath)
        process.arguments = ["-listallnetworkservices"]
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        return output
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.hasPrefix("An asterisk") && !$0.hasPrefix("*") && !$0.isEmpty }
    }

    func currentMode(for service: String) -> DNSMode? {
        let servers = currentServers(for: service)

        if servers.isEmpty {
            return .automatic
        }

        if servers.count == DNSConfiguration.customServers.count,
           zip(servers, DNSConfiguration.customServers).allSatisfy({ $0 == $1 }) {
            return .custom
        }

        return nil
    }

    func currentServers(for service: String) -> [String] {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: networkSetupPath)
        process.arguments = ["-getdnsservers", service]
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty else {
            return []
        }

        let lowercased = output.lowercased()
        if lowercased.contains("there aren't any dns servers") ||
            lowercased.contains("empty") {
            return []
        }

        return output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func apply(mode: DNSMode) async throws {
        let services = listEnabledNetworkServices()
        guard !services.isEmpty else {
            throw DNSManagerError.noNetworkServices
        }

        var commands: [String] = []
        for service in services {
            let escapedService = shellEscape(service)
            switch mode {
            case .automatic:
                commands.append("\(networkSetupPath) -setdnsservers \(escapedService) Empty")
            case .custom:
                let servers = DNSConfiguration.customServers.map(shellEscape).joined(separator: " ")
                commands.append("\(networkSetupPath) -setdnsservers \(escapedService) \(servers)")
            }
        }

        let combined = commands.joined(separator: " && ")
        try await runWithAdministratorPrivileges(command: combined)
    }

    private func shellEscape(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func runWithAdministratorPrivileges(command: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let escapedCommand = command
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")

                let source = """
                do shell script "\(escapedCommand)" with administrator privileges
                """

                var error: NSDictionary?
                guard let script = NSAppleScript(source: source) else {
                    continuation.resume(throwing: DNSManagerError.commandFailed("Could not create authorization script."))
                    return
                }

                _ = script.executeAndReturnError(&error)

                if let error {
                    let message = (error[NSAppleScript.errorMessage] as? String) ?? "Unknown error"
                    if message.localizedCaseInsensitiveContains("canceled") ||
                        message.localizedCaseInsensitiveContains("cancelled") {
                        continuation.resume(throwing: DNSManagerError.authorizationCancelled)
                    } else {
                        continuation.resume(throwing: DNSManagerError.commandFailed(message))
                    }
                    return
                }

                continuation.resume(returning: ())
            }
        }
    }
}
