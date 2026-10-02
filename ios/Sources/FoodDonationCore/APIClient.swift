import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum APIError: Error, Equatable {
    case invalidResponse
    case server(status: Int, message: String)
    case encoding
}

extension APIError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidResponse: "The server returned an invalid response."
        case let .server(_, message): message
        case .encoding: "The request could not be encoded."
        }
    }
}

public actor FoodDonationAPI {
    private let baseURL: URL
    private let auth: AuthContext
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(baseURL: URL, auth: AuthContext, session: URLSession = .shared) {
        self.baseURL = baseURL; self.auth = auth; self.session = session
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; self.encoder = encoder
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; self.decoder = decoder
    }

    public func createSession(_ body: CreateSessionRequest) async throws -> IntakeSessionResponse {
        try await send("v1/intake-sessions", method: "POST", body: body)
    }

    public func lookupProduct(_ body: ProductLookupRequest) async throws -> ProductLookupResponse {
        try await send("v1/product-lookups", method: "POST", body: body)
    }

    public func createItem(sessionID: UUID, body: CreateItemRequest, idempotencyKey: String) async throws -> IntakeItemResponse {
        try await send("v1/intake-sessions/\(sessionID.uuidString)/items", method: "POST", body: body, idempotencyKey: idempotencyKey)
    }

    public func uploadEvidence(itemID: UUID, jpegData: Data, capturedAt: Date) async throws -> EvidenceAsset {
        let boundary = "FoodDonation-\(UUID().uuidString)"
        var body = Data()
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"capturedAt\"\r\n\r\n\(ISO8601DateFormatter().string(from: capturedAt))\r\n".utf8))
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"photo\"; filename=\"date-label.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8))
        body.append(jpegData)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var request = URLRequest(url: baseURL.appending(path: "v1/intake-items/\(itemID.uuidString)/evidence"))
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        authenticate(&request)
        return try decoder.decode(EvidenceAsset.self, from: try await validatedData(for: request))
    }

    public func evidence(itemID: UUID) async throws -> EvidenceListResponse {
        try await sendURL(baseURL.appending(path: "v1/intake-items/\(itemID.uuidString)/evidence"), method: "GET", bodyData: nil, idempotencyKey: nil)
    }

    public func evidenceImage(itemID: UUID, evidenceID: UUID) async throws -> Data {
        var request = URLRequest(url: baseURL.appending(path: "v1/intake-items/\(itemID.uuidString)/evidence/\(evidenceID.uuidString)"))
        request.httpMethod = "GET"
        authenticate(&request)
        return try await validatedData(for: request)
    }

    public func submitItem(itemID: UUID, body: SubmitItemRequest, idempotencyKey: String) async throws -> SubmitItemResponse {
        try await send("v1/intake-items/\(itemID.uuidString)/submit", method: "POST", body: body, idempotencyKey: idempotencyKey)
    }

    public func adminReviewQueue() async throws -> AdminReviewQueueResponse {
        try await sendURL(baseURL.appending(path: "v1/admin/review-queue"), method: "GET", bodyData: nil, idempotencyKey: nil)
    }

    public func decideIntakeItem(itemID: UUID, body: AdminDecisionRequest, idempotencyKey: String) async throws -> AdminDecisionResponse {
        try await send("v1/admin/intake-items/\(itemID.uuidString)/decision", method: "POST", body: body, idempotencyKey: idempotencyKey)
    }

    public func donationItems(search: String? = nil, sort: String = "received") async throws -> DonationDashboardResponse {
        var components = URLComponents(url: baseURL.appending(path: "v1/donation-items"), resolvingAgainstBaseURL: false)!
        var queryItems = [URLQueryItem(name: "sort", value: sort)]
        if let search, !search.isEmpty { queryItems.append(URLQueryItem(name: "search", value: search)) }
        components.queryItems = queryItems
        return try await sendURL(components.url!, method: "GET", bodyData: nil, idempotencyKey: nil)
    }

    private func send<Request: Encodable, Response: Decodable>(_ path: String, method: String, body: Request, idempotencyKey: String? = nil) async throws -> Response {
        let data: Data
        do { data = try encoder.encode(body) } catch { throw APIError.encoding }
        return try await sendURL(baseURL.appending(path: path), method: method, bodyData: data, idempotencyKey: idempotencyKey)
    }

    private func sendURL<Response: Decodable>(_ url: URL, method: String, bodyData: Data?, idempotencyKey: String?) async throws -> Response {
        var request = URLRequest(url: url); request.httpMethod = method; request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        authenticate(&request)
        if let idempotencyKey { request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key") }
        return try decoder.decode(Response.self, from: try await validatedData(for: request))
    }

    private func authenticate(_ request: inout URLRequest) {
        request.setValue(auth.userID, forHTTPHeaderField: "x-user-id")
        request.setValue(auth.organizationID, forHTTPHeaderField: "x-organization-id")
        request.setValue(auth.role.rawValue, forHTTPHeaderField: "x-role")
    }

    private func validatedData(for request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let messageValue = payload?["message"]
            let message = (messageValue as? String) ?? (messageValue as? [String])?.joined(separator: "\n") ?? "Request failed"
            throw APIError.server(status: http.statusCode, message: message)
        }
        return data
    }
}
