import Foundation

enum DDNSClientError: LocalizedError {
    case invalidResponse
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from DDNS server."
        case .emptyResponse:
            return "Empty response from DDNS server."
        }
    }
}

final class DDNSClient {
    static let shared = DDNSClient()

    private let session: URLSession

    private init(session: URLSession = .shared) {
        self.session = session
    }

    func refreshIP() async throws -> String {
        var request = URLRequest(url: DNSConfiguration.ddnsUpdateURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 30

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DDNSClientError.invalidResponse
        }

        let body = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if body.isEmpty {
            throw DDNSClientError.emptyResponse
        }

        if !(200 ... 299).contains(httpResponse.statusCode) {
            return body
        }

        return body
    }

    static func isIPAddress(_ text: String) -> Bool {
        let pattern = #"^(?:(?:25[0-5]|2[0-4]\d|[01]?\d?\d)(?:\.|$)){4}$"#
        return text.range(of: pattern, options: .regularExpression) != nil
    }
}
