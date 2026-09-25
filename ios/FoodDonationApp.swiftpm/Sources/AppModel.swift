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
    let scan: ParsedScan
    let candidate: ProductCandidate
    var productName: String
    var brand: String
    var quantity = 1.0
    var quantityUnit = "each"
    var dateType = "best_if_used_by"
    var hasPrintedDate = true
    var dateValue = Calendar.current.date(byAdding: .day, value: 30, to: .now) ?? .now
    var dateLabelRaw = ""
    var storageType = "shelf_stable"
    var packageCondition = "acceptable"
    var temperatureStatus = "not_applicable"
    var calories: Double?
    var calorieBasis: String?

    init(scan: ParsedScan, candidate: ProductCandidate) {
        self.scan = scan
        self.candidate = candidate
        productName = candidate.name
        brand = candidate.brand ?? ""
        calories = candidate.calories.map { NSDecimalNumber(decimal: $0).doubleValue }
        calorieBasis = candidate.calorieBasis
    }
}

@MainActor
@Observable
final class AppModel {
    private enum Defaults {
        static let organizationID = "00000000-0000-4000-8000-000000000001"
        static let locationID = "00000000-0000-4000-8000-000000000101"
        static let userID = "regular-demo"
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

    private(set) var dashboardState: DashboardLoadState = .idle
    private(set) var dashboardItems: [DonationDashboardItem] = []
    private(set) var isLookingUp = false

    init(defaults: UserDefaults = .standard) {
        apiURL = defaults.string(forKey: "apiURL") ?? Defaults.apiURL
        organizationID = defaults.string(forKey: "organizationID") ?? Defaults.organizationID
        locationID = defaults.string(forKey: "locationID") ?? Defaults.locationID
        userID = defaults.string(forKey: "userID") ?? Defaults.userID
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
        guard let candidate = response.candidates.first else {
            throw AppValidationError("No catalog product was found. Manual product creation is the next intake capability.")
        }
        return IntakeDraft(scan: scan, candidate: candidate)
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

        let client = try api()
        let session = try await client.createSession(.init(
            receivingLocationId: storageLocationID,
            receivedAt: .now,
            sourceChannel: "walk_in",
            clientMutationId: "ios-session-\(UUID().uuidString)"
        ))
        let item = try await client.createItem(sessionID: session.id, body: .init(
            productId: draft.candidate.productId,
            productName: draft.productName,
            brand: draft.brand.nilIfBlank,
            identitySource: identitySource(for: draft.scan.scheme),
            quantity: Decimal(draft.quantity),
            quantityUnit: draft.quantityUnit,
            dateType: draft.hasPrintedDate ? draft.dateType : "none",
            dateValue: draft.hasPrintedDate ? Self.dateFormatter.string(from: draft.dateValue) : nil,
            dateLabelRaw: draft.dateLabelRaw.nilIfBlank,
            storageType: draft.storageType,
            storageLocationId: storageLocationID,
            packageCondition: draft.packageCondition,
            temperatureStatus: draft.temperatureStatus,
            calorieStatus: draft.calories == nil ? "not_labeled" : "recorded",
            calories: draft.calories.map { Decimal($0) },
            calorieBasis: draft.calorieBasis,
            allergens: acceptedAllergens(from: draft.candidate.allergens),
            requiredFieldConfidence: [draft.candidate.confidence, 1, 1]
        ))
        let response = try await client.submitItem(
            itemID: item.id,
            body: .init(userReviewedAt: .now),
            idempotencyKey: "ios-submit-\(UUID().uuidString)"
        )
        await loadDashboard()
        return response
    }

    func resetDevelopmentSettings() {
        apiURL = Defaults.apiURL
        organizationID = Defaults.organizationID
        locationID = Defaults.locationID
        userID = Defaults.userID
    }

    private func api() throws -> FoodDonationAPI {
        guard let url = URL(string: apiURL), UUID(uuidString: organizationID) != nil else {
            throw AppValidationError("Check the API URL and organization ID in Settings.")
        }
        return FoodDonationAPI(
            baseURL: url,
            auth: .init(userID: userID, organizationID: organizationID, role: .regularUser)
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
