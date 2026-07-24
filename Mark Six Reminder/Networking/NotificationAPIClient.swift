import Foundation

/// The device preference document accepted by the Worker registration endpoint.
struct NotificationRegistration: Encodable, Sendable {
    let installationId: String
    let deviceToken: String
    let threshold: Int
    let enabled: Bool
    let apnsEnvironment: String
}

/// Synchronizes one installation's latest notification preference with the Worker.
struct NotificationAPIClient: Sendable {
    let baseURL: URL

    /// Creates or replaces the notification registration for this installation.
    func register(_ registration: NotificationRegistration) async throws {
        let url = baseURL
            .appending(path: "v1")
            .appending(path: "notification-subscriptions")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(registration)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw JackpotAPIError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let errorEnvelope = try? JSONDecoder().decode(NotificationAPIErrorEnvelope.self, from: data)
            throw JackpotAPIError.server(
                statusCode: httpResponse.statusCode,
                message: errorEnvelope?.error.message
            )
        }
    }
}

/// The error envelope returned by notification registration routes.
private struct NotificationAPIErrorEnvelope: Decodable {
    let error: NotificationAPIErrorPayload
}

/// A user-safe backend error associated with notification registration.
private struct NotificationAPIErrorPayload: Decodable {
    let code: String
    let message: String
}
