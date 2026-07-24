import Foundation

/// Errors produced while communicating with the Jackpot Alert Worker.
enum JackpotAPIError: LocalizedError {
    case invalidConfiguration
    case invalidResponse
    case server(statusCode: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            "尚未設定 Jackpot Alert API 網址。"
        case .invalidResponse:
            "伺服器回傳了無法識別的資料。"
        case let .server(statusCode, message):
            message ?? "伺服器暫時無法提供資料（\(statusCode)）。"
        }
    }
}

/// A small URLSession client for the public Worker API.
struct JackpotAPIClient: Sendable {
    let baseURL: URL

    /// Fetches the latest validated next-draw snapshot.
    func currentDraw() async throws -> DrawInfo {
        let url = baseURL
            .appending(path: "v1")
            .appending(path: "draws")
            .appending(path: "current")

        return try await fetchDraw(from: url)
    }

    /// Fetches one persisted draw by its official stable identifier.
    func draw(id: String) async throws -> DrawInfo {
        let url = baseURL
            .appending(path: "v1")
            .appending(path: "draws")
            .appending(path: id)

        return try await fetchDraw(from: url)
    }

    /// Sends a bounded request and decodes the Worker's common draw envelope.
    private func fetchDraw(from url: URL) async throws -> DrawInfo {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw JackpotAPIError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let errorEnvelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data)
            throw JackpotAPIError.server(
                statusCode: httpResponse.statusCode,
                message: errorEnvelope?.error.message
            )
        }

        do {
            return try JSONDecoder().decode(APIEnvelope<DrawInfo>.self, from: data).data
        } catch {
            throw JackpotAPIError.invalidResponse
        }
    }
}

/// The common success envelope returned by the Worker.
private struct APIEnvelope<Value: Decodable>: Decodable {
    let data: Value
}

/// The common error envelope returned by the Worker.
private struct APIErrorEnvelope: Decodable {
    let error: APIErrorPayload
}

/// A user-safe error returned by the Worker.
private struct APIErrorPayload: Decodable {
    let code: String
    let message: String
}
