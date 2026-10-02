import CryptoKit
import FoodDonationCore
import Foundation
import Observation

enum DashboardLoadState {
    case idle
    case loading
    case loaded
    case failed(String)
}

struct IntakeDraft: Identifiable {
    let id = UUID()
    let scan: ParsedScan?
    let candidate: ProductCandidate?
    var productName: String
    var brand: String
    var quantity = 1.0
    var quantityUnit = "each"
    var dateType = "best_if_used_by"
    var hasPrintedDate = false
    var dateValue: Date?
    var dateLabelRaw = ""
    var dateSource = "Not captured"
    var dateConfidence: Double?
    var dateConfirmed = false
    var packagePhotoData: Data?
    var packagePhotoCapturedAt: Date?
    var storageType = "shelf_stable"
    var packageCondition = "acceptable"
    var temperatureStatus = "not_applicable"
    var calories: Double?
    var calorieBasis: String?

    init(scan: ParsedScan? = nil, candidate: ProductCandidate? = nil) {
        self.scan = scan
        self.candidate = candidate
        productName = candidate?.name ?? ""
        brand = candidate?.brand ?? ""
        calories = candidate?.calories.map { NSDecimalNumber(decimal: $0).doubleValue }
        calorieBasis = candidate?.calorieBasis
    }
}

@MainActor
@Observable
final class AppModel {
    private struct SubmissionAttempt {
        let itemID: UUID
        let idempotencyKey: String
        let itemBody: Data
        let photoHash: String?
    }

    private struct AdminDecisionAttempt {
        let decision: String
        let reason: String
        let idempotencyKey: String
    }

    private enum Defaults {
        static let organizationID = "00000000-0000-4000-8000-000000000001"
        static let locationID = "00000000-0000-4000-8000-000000000101"
        static let userID = "regular-demo"
        static let userRole: UserRole = .regularUser
        #if targetEnvironment(simulator)
        static let apiURL = "http://127.0.0.1:3000"
        #else
        static let apiURL = "http://192.168.0.101:3000"
        #endif
    }

    var apiURL: String { didSet { save(apiURL, key: "apiURL") } }
    var organizationID: String { didSet { save(organizationID, key: "organizationID") } }
    var locationID: String { didSet { save(locationID, key: "locationID") } }
    var userID: String { didSet { save(userID, key: "userID") } }
    var userRole: UserRole { didSet { save(userRole.rawValue, key: "userRole") } }

    private(set) var dashboardState: DashboardLoadState = .idle
    private(set) var dashboardItems: [DonationDashboardItem] = []
    private(set) var isLookingUp = false
    private(set) var reviewQueueState: DashboardLoadState = .idle
    private(set) var reviewItems: [AdminReviewItem] = []
    private var submissionAttempts: [UUID: SubmissionAttempt] = [:]
    private var adminDecisionAttempts: [UUID: AdminDecisionAttempt] = [:]

    init(defaults: UserDefaults = .standard) {
        apiURL = defaults.string(forKey: "apiURL") ?? Defaults.apiURL
        organizationID = defaults.string(forKey: "organizationID") ?? Defaults.organizationID
        locationID = defaults.string(forKey: "locationID") ?? Defaults.locationID
        userID = defaults.string(forKey: "userID") ?? Defaults.userID
        userRole = UserRole(rawValue: defaults.string(forKey: "userRole") ?? "") ?? Defaults.userRole
    }

    func loadDashboard() async {
        dashboardState = .loading
        do {
            dashboardItems = try await api().donationItems().items
            dashboardState = .loaded
        } catch {
            dashboardState = .failed(error.localizedDescription)
        }
    }

    func prepareDraft(rawValue: String) async throws -> IntakeDraft {
        isLookingUp = true
        defer { isLookingUp = false }

        let scan = ScanParser.parse(rawValue)
        guard scan.normalizedGTIN != nil else {
            throw AppValidationError("Scan a checksum-valid UPC, EAN, or GTIN for this MVP.")
        }
        let response = try await api().lookupProduct(.init(rawCode: scan.raw, scheme: scan.scheme))
        return IntakeDraft(scan: scan, candidate: response.candidates.first)
    }

    func manualDraft(rawValue: String? = nil) -> IntakeDraft {
        let scan = rawValue.map(ScanParser.parse)
        return IntakeDraft(scan: scan)
    }

    func submit(_ draft: IntakeDraft) async throws -> SubmitItemResponse {
        guard let storageLocationID = UUID(uuidString: locationID) else {
            throw AppValidationError("The storage location ID in Settings is not a valid UUID.")
        }
        guard !draft.productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppValidationError("Product name is required.")
        }
        guard draft.quantity > 0 else {
            throw AppValidationError("Quantity must be greater than zero.")
        }
        if draft.hasPrintedDate && (draft.dateValue == nil || !draft.dateConfirmed) {
            throw AppValidationError("Confirm the actual printed date before submitting.")
        }

        let itemBody = CreateItemRequest(
            productId: draft.candidate?.productId,
            productName: draft.productName,
            brand: draft.brand.nilIfBlank,
            identitySource: draft.scan?.normalizedGTIN == nil ? "manual" : identitySource(for: draft.scan?.scheme ?? .unknown),
            scannedCode: draft.scan?.raw.nilIfBlank,
            quantity: Decimal(draft.quantity),
            quantityUnit: draft.quantityUnit,
            dateType: draft.hasPrintedDate ? draft.dateType : "none",
            dateValue: draft.hasPrintedDate ? draft.dateValue.map(Self.dateFormatter.string(from:)) : nil,
            dateLabelRaw: draft.hasPrintedDate ? draft.dateLabelRaw.nilIfBlank : nil,
            storageType: draft.storageType,
            storageLocationId: storageLocationID,
            packageCondition: draft.packageCondition,
            temperatureStatus: draft.temperatureStatus,
            calorieStatus: draft.calories == nil ? "not_labeled" : "recorded",
            calories: draft.calories.map { Decimal($0) },
            calorieBasis: draft.calorieBasis,
            allergens: acceptedAllergens(from: draft.candidate?.allergens ?? []),
            requiredFieldConfidence: [draft.candidate?.confidence ?? 0.3, 1, draft.hasPrintedDate ? 1 : 0.5]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let encodedBody = try encoder.encode(itemBody)
        let photoHash = draft.packagePhotoData.map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() }
        let client = try api()
        let attempt: SubmissionAttempt
        if let pending = submissionAttempts[draft.id], pending.itemBody == encodedBody, pending.photoHash == photoHash {
            attempt = pending
        } else {
            let session = try await client.createSession(.init(
                receivingLocationId: storageLocationID,
                receivedAt: .now,
                sourceChannel: "walk_in",
                clientMutationId: "ios-session-\(UUID().uuidString)"
            ))
            let item = try await client.createItem(sessionID: session.id, body: itemBody)
            attempt = SubmissionAttempt(
                itemID: item.id,
                idempotencyKey: "ios-submit-\(UUID().uuidString)",
                itemBody: encodedBody,
                photoHash: photoHash
            )
            submissionAttempts[draft.id] = attempt
        }
        if let photo = draft.packagePhotoData {
            _ = try await client.uploadEvidence(
                itemID: attempt.itemID,
                jpegData: photo,
                capturedAt: draft.packagePhotoCapturedAt ?? .now
            )
        }
        let response = try await client.submitItem(
            itemID: attempt.itemID,
            body: .init(userReviewedAt: .now),
            idempotencyKey: attempt.idempotencyKey
        )
        submissionAttempts[draft.id] = nil
        await loadDashboard()
        return response
    }

    func evidence(for itemID: UUID) async throws -> [EvidenceAsset] {
        try await api().evidence(itemID: itemID).items
    }

    func evidenceImage(for itemID: UUID, evidenceID: UUID) async throws -> Data {
        try await api().evidenceImage(itemID: itemID, evidenceID: evidenceID)
    }

    func loadReviewQueue() async {
        guard userRole == .admin else {
            reviewItems = []
            reviewQueueState = .idle
            return
        }
        reviewQueueState = .loading
        do {
            reviewItems = try await api().adminReviewQueue().items
            reviewQueueState = .loaded
        } catch {
            reviewQueueState = .failed(error.localizedDescription)
        }
    }

    func decide(_ item: AdminReviewItem, decision: String, reason: String) async throws -> AdminDecisionResponse {
        guard userRole == .admin else { throw AppValidationError("Switch to an admin identity in Settings.") }
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReason.isEmpty else { throw AppValidationError("Enter a reason for this decision.") }
        let attempt: AdminDecisionAttempt
        if let pending = adminDecisionAttempts[item.id] {
            guard pending.decision == decision && pending.reason == trimmedReason else {
                throw AppValidationError("Retry the previous decision before changing its action or reason.")
            }
            attempt = pending
        } else {
            attempt = AdminDecisionAttempt(decision: decision, reason: trimmedReason, idempotencyKey: "ios-admin-\(UUID().uuidString)")
            adminDecisionAttempts[item.id] = attempt
        }
        let response = try await api().decideIntakeItem(
            itemID: item.id,
            body: .init(decision: attempt.decision, reason: attempt.reason),
            idempotencyKey: attempt.idempotencyKey
        )
        adminDecisionAttempts[item.id] = nil
        await loadReviewQueue()
        await loadDashboard()
        return response
    }

    func resetDevelopmentSettings() {
        apiURL = Defaults.apiURL
        organizationID = Defaults.organizationID
        locationID = Defaults.locationID
        userID = Defaults.userID
        userRole = Defaults.userRole
    }

    private func api() throws -> FoodDonationAPI {
        guard let url = URL(string: apiURL), UUID(uuidString: organizationID) != nil else {
            throw AppValidationError("Check the API URL and organization ID in Settings.")
        }
        return FoodDonationAPI(
            baseURL: url,
            auth: .init(userID: userID, organizationID: organizationID, role: userRole)
        )
    }

    private func save(_ value: String, key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    private func identitySource(for scheme: ScanCodeScheme) -> String {
        switch scheme {
        case .gs1: "gs1"
        case .qr: "qr"
        default: "barcode"
        }
    }

    private func acceptedAllergens(from values: [AllergenDeclaration]) -> [AllergenDeclaration] {
        let supported = Set(["milk", "egg", "fish", "crustacean_shellfish", "tree_nuts", "peanuts", "wheat", "soybeans", "sesame"])
        return values.filter { supported.contains($0.code) }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

struct AppValidationError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
