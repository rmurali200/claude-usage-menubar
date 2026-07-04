import Foundation

struct UsageWindow: Decodable {
    let utilization: Double
    let resetsAt: Date

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        utilization = try container.decode(Double.self, forKey: .utilization)
        let dateString = try container.decode(String.self, forKey: .resetsAt)
        guard let date = ISO8601DateFormatter.withFractionalSeconds.date(from: dateString)
            ?? ISO8601DateFormatter().date(from: dateString) else {
            throw DecodingError.dataCorruptedError(forKey: .resetsAt, in: container, debugDescription: "Unrecognized date format: \(dateString)")
        }
        resetsAt = date
    }
}

extension ISO8601DateFormatter {
    static let withFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

struct UsageResponse: Decodable {
    let fiveHour: UsageWindow?
    let sevenDay: UsageWindow?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}

enum UsageAPIError: Error {
    case httpError(Int, String)
}

enum UsageAPI {
    static func fetch() async throws -> UsageResponse {
        let token = try await OAuthClient.validAccessToken()
        var request = URLRequest(url: URL(string: OAuthConfig.usageURL)!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UsageAPIError.httpError(-1, "no response")
        }
        if http.statusCode == 401 {
            // token might have just been invalidated server-side; one retry after forcing refresh
            KeychainStore.load().map { stored in
                KeychainStore.save(StoredTokens(accessToken: stored.accessToken, refreshToken: stored.refreshToken, expiresAt: Date.distantPast))
            }
            let retryToken = try await OAuthClient.validAccessToken()
            var retryRequest = request
            retryRequest.setValue("Bearer \(retryToken)", forHTTPHeaderField: "Authorization")
            let (retryData, retryResponse) = try await URLSession.shared.data(for: retryRequest)
            guard let retryHttp = retryResponse as? HTTPURLResponse, (200...299).contains(retryHttp.statusCode) else {
                throw UsageAPIError.httpError((retryResponse as? HTTPURLResponse)?.statusCode ?? -1, String(data: retryData, encoding: .utf8) ?? "")
            }
            return try JSONDecoder().decode(UsageResponse.self, from: retryData)
        }
        guard (200...299).contains(http.statusCode) else {
            throw UsageAPIError.httpError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return try JSONDecoder().decode(UsageResponse.self, from: data)
    }
}
