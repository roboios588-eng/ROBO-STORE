
import Foundation
import UIKit

struct APIProduct: Codable, Identifiable {
    var id: String
    var name: String
    var description: String?
    var price: Double
    var category: String?
}

struct APIOrder: Codable, Identifiable {
    var id: String
    var productName: String?
    var amount: Double?
    var status: String?
    var paymentStatus: String?
    var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, status, amount
        case productName = "product_name"
        case paymentStatus = "payment_status"
        case createdAt = "created_at"
    }
}

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case server(String)
    case missingToken

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid API URL."
        case .invalidResponse: return "Invalid server response."
        case .server(let message): return message
        case .missingToken: return "Please log in again."
        }
    }
}

final class APIClient {
    static let shared = APIClient()

    private let baseURL =
      "https://project--aa8a6a4b-7f70-4cfc-9a0c-cb14a59039e2.lovable.app/api/public/v1"

    private init() {}

    private func request(
        _ path: String,
        method: String = "GET",
        body: Data? = nil,
        authenticated: Bool = true
    ) async throws -> Data {
        guard let url = URL(string: baseURL + "/" + path) else {
            throw APIError.invalidURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        req.timeoutInterval = 30

        if authenticated {
            guard let token = KeychainTokenStore.shared.read() else {
                throw APIError.missingToken
            }
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: req)

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8)
                ?? "Server error: \(http.statusCode)"
            throw APIError.server(message)
        }

        return data
    }

    func login(identifier: String, password: String) async throws {
        let payload: [String: String] = [
            "identifier": identifier,
            "email": identifier,
            "username": identifier,
            "password": password
        ]

        let body = try JSONSerialization.data(withJSONObject: payload)
        let data = try await request(
            "auth/login",
            method: "POST",
            body: body,
            authenticated: false
        )

        let json = try JSONSerialization.jsonObject(with: data)
        guard let object = json as? [String: Any] else {
            throw APIError.invalidResponse
        }

        let token = (object["access_token"] as? String)
            ?? (object["token"] as? String)
            ?? ((object["data"] as? [String: Any])?["access_token"] as? String)
            ?? ((object["data"] as? [String: Any])?["token"] as? String)

        guard let token, !token.isEmpty else {
            throw APIError.server("Login response did not contain an access token.")
        }

        try KeychainTokenStore.shared.save(token)
    }

    func register(
        username: String,
        email: String,
        password: String
    ) async throws {
        let payload: [String: String] = [
            "username": username,
            "email": email,
            "password": password
        ]

        let body = try JSONSerialization.data(withJSONObject: payload)
        _ = try await request(
            "auth/register",
            method: "POST",
            body: body,
            authenticated: false
        )
    }

    func products() async throws -> [APIProduct] {
        let data = try await request("products")
        return try decodeArray(APIProduct.self, from: data)
    }

    func orders() async throws -> [APIOrder] {
        let data = try await request("orders")
        return try decodeArray(APIOrder.self, from: data)
    }

    func createOrder(productID: String) async throws {
        let body = try JSONSerialization.data(
            withJSONObject: ["product_id": productID]
        )
        _ = try await request("orders", method: "POST", body: body)
    }

    func uploadPaymentProof(
        orderID: String,
        transactionReference: String,
        image: UIImage
    ) async throws {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw APIError.server("Could not process the screenshot.")
        }

        guard imageData.count <= 5 * 1024 * 1024 else {
            throw APIError.server("Screenshot must be 5 MB or smaller.")
        }

        guard let url = URL(
            string: "\(baseURL)/orders/\(orderID)/payment"
        ) else {
            throw APIError.invalidURL
        }

        guard let token = KeychainTokenStore.shared.read() else {
            throw APIError.missingToken
        }

        let boundary = UUID().uuidString
        var body = Data()

        func append(_ string: String) {
            body.append(Data(string.utf8))
        }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"transaction_reference\"\r\n\r\n")
        append("\(transactionReference)\r\n")

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"proof\"; filename=\"payment.jpg\"\r\n")
        append("Content-Type: image/jpeg\r\n\r\n")
        body.append(imageData)
        append("\r\n--\(boundary)--\r\n")

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        req.httpBody = body
        req.timeoutInterval = 60

        let (_, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.server(
                "Payment upload failed. Server returned \(http.statusCode)."
            )
        }
    }

    func logout() {
        KeychainTokenStore.shared.delete()
    }

    private func decodeArray<T: Decodable>(
        _ type: T.Type,
        from data: Data
    ) throws -> [T] {
        let decoder = JSONDecoder()

        if let array = try? decoder.decode([T].self, from: data) {
            return array
        }

        if let wrapper = try? decoder.decode(DataWrapper<T>.self, from: data) {
            return wrapper.data
        }

        throw APIError.server(
            "The API response format does not match the app models."
        )
    }
}

private struct DataWrapper<T: Decodable>: Decodable {
    let data: [T]
}
