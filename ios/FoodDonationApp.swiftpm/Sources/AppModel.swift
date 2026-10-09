import FoodDonationCore
import Foundation
import Observation

enum DashboardLoadState {
    case idle
    case loading
    case loaded
    case failed(String)
}

enum DashboardSort: String, CaseIterable {
    case received
    case expiration
    case category
    case name

    var title: String {
        switch self {
        case .received: "Received date (newest)"
        case .expiration: "Closest printed date"
        case .category: "Category (A–Z)"
        case .name: "Product name (A–Z)"
        }
    }
}

struct IntakePhoto: Codable, Identifiable, Sendable {
    let id: UUID
    var jpegData: Data?
    let capturedAt: Date
}

struct IntakeDraft: Codable, Identifiable, Sendable {
    let id: UUID
    let scan: ParsedScan?
    let candidate: ProductCandidate?
    var productName: String
    var brand: String
    var category: String?
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
    // Optional so drafts saved by earlier app versions remain decodable.
    var referencePhotos: [IntakePhoto]?
    // Optional for drafts saved by earlier app versions.
    var usedPhotoSuggestions: Bool?
    // Optional so drafts saved by earlier app versions remain decodable.
    var identityEdited: Bool?
    // A correction to catalog nutrition is reviewed instead of silently auto-accepted.
    var labelEdited: Bool?
    // Optional so older saved drafts still decode without manually edited allergens.
    var allergenOverrides: [AllergenDeclaration]?
    var storageType = "shelf_stable"
    var packageCondition = "acceptable"
    var temperatureStatus = "not_applicable"
    var calories: Double?
    var calorieBasis: String?
    var servingSize: String?
    // Optional to preserve decoding of drafts saved before dietary claims existed.
    var dietaryClaims: [String]?
    var otherLabelClaims: [String]?
    var dietaryClaimsConfirmed: Bool?

    init(id: UUID = UUID(), scan: ParsedScan? = nil, candidate: ProductCandidate? = nil) {
        self.id = id
        self.scan = scan
        self.candidate = candidate
        productName = candidate?.name ?? ""
        brand = candidate?.brand ?? ""
        category = FoodCategory.from(raw: candidate?.category).rawValue
        calories = candidate?.calories.map { NSDecimalNumber(decimal: $0).doubleValue }
        calorieBasis = candidate?.calorieBasis
        servingSize = candidate?.servingSize
    }

    var submissionIssues: [String] {
        var issues: [String] = []
        if productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("Enter a product name in Product. Add a front-label photo or type the name if AI could not read it.")
        }
        if !quantity.isFinite || quantity <= 0 {
            issues.append("Enter a quantity greater than zero.")
        }
        if let calories, !calories.isFinite || calories < 0 {
            issues.append("Correct the calories value; it must be zero or greater.")
        }
        let photoCount = (referencePhotos ?? []).count + (packagePhotoData == nil ? 0 : 1)
        if photoCount > 8 {
            issues.append("Remove package photos until there are no more than eight.")
        }
        if hasPrintedDate {
            if dateValue == nil {
                issues.append("Set the printed date, or turn off ‘Package has a printed date’ if none is visible.")
            } else if !dateConfirmed {
                issues.append("Turn on ‘I checked the date and type on the package’ after verifying both fields.")
            }
        }
        if (!(dietaryClaims ?? []).isEmpty || !(otherLabelClaims ?? []).isEmpty) && dietaryClaimsConfirmed != true {
            issues.append("Turn on ‘I checked these claims on the package’ after verifying every selected claim.")
        }
        return issues
    }
}

@MainActor
@Observable
final class AppModel {
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
    var dashboardSort: DashboardSort = .received

    private(set) var dashboardState: DashboardLoadState = .idle
    private(set) var dashboardItems: [DonationDashboardItem] = []
    private(set) var isLookingUp = false
    private(set) var reviewQueueState: DashboardLoadState = .idle
    private(set) var reviewItems: [AdminReviewItem] = []
    private(set) var savedDrafts: [SavedIntakeDraft] = []
    private(set) var savedDraftsError: String?
    private var dashboardRequestID = UUID()
    private let draftStore: LocalIntakeDraftStore
    private var adminDecisionAttempts: [UUID: AdminDecisionAttempt] = [:]

    init(defaults: UserDefaults = .standard, draftDirectory: URL? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        draftStore = LocalIntakeDraftStore(directory: draftDirectory ?? support.appending(path: "FoodDonation/SavedDrafts", directoryHint: .isDirectory))
        apiURL = defaults.string(forKey: "apiURL") ?? Defaults.apiURL
        organizationID = defaults.string(forKey: "organizationID") ?? Defaults.organizationID
        locationID = defaults.string(forKey: "locationID") ?? Defaults.locationID
        userID = defaults.string(forKey: "userID") ?? Defaults.userID
        userRole = UserRole(rawValue: defaults.string(forKey: "userRole") ?? "") ?? Defaults.userRole
    }

    func loadSavedDrafts() async {
        do {
            savedDrafts = try await draftStore.loadAll()
            savedDraftsError = nil
        } catch {
            savedDraftsError = "Could not read saved drafts: \(error.localizedDescription)"
        }
    }

    func deleteSavedDraft(id: UUID) async throws {
        guard savedDrafts.contains(where: { $0.id == id }) else { return }
        try await draftStore.delete(id: id)
        savedDrafts.removeAll { $0.id == id }
        savedDraftsError = nil
    }

    func saveDraft(_ draft: IntakeDraft) async throws {
        var record = savedDrafts.first { $0.id == draft.id } ?? newSavedDraft(draft)
        guard !record.isLocked else { throw AppValidationError("This draft is already queued for submission. Retry it instead of editing.") }
        try verifyIdentity(for: record)
        record.draft = draft
        record.savedAt = .now
        try await persist(record)
    }

    func isDraftLocked(_ id: UUID) -> Bool {
        savedDrafts.first { $0.id == id }?.isLocked ?? false
    }

    func loadDashboard() async {
        let requestID = UUID()
        dashboardRequestID = requestID
        let sort = dashboardSort.rawValue
        dashboardState = .loading
        do {
            let items = try await api().donationItems(sort: sort).items
            guard dashboardRequestID == requestID else { return }
            dashboardItems = items
            dashboardState = .loaded
        } catch {
            guard dashboardRequestID == requestID else { return }
            dashboardState = .failed(error.localizedDescription)
        }
    }

    func searchDonations(query: String, sort: DashboardSort) async throws -> [DonationDashboardItem] {
        try await api().donationItems(search: query, sort: sort.rawValue).items
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

    func analyzePhotos(_ photos: [Data]) async throws -> PhotoAnalysisResponse {
        guard !photos.isEmpty && photos.count <= 8 else { throw AppValidationError("Add one to eight package photos first.") }
        return try await api().analyzePhotos(photos)
    }

    func submit(_ draft: IntakeDraft) async throws -> SubmitItemResponse {
        var record = savedDrafts.first { $0.id == draft.id } ?? newSavedDraft(draft)
        try verifyIdentity(for: record)
        let submittedDraft = record.isLocked ? record.draft : draft
        if let issue = submittedDraft.submissionIssues.first { throw AppValidationError(issue) }
        guard let storageLocationID = UUID(uuidString: record.locationID) else {
            throw AppValidationError("The storage location ID in Settings is not a valid UUID.")
        }
        if !record.isLocked {
            record.draft = submittedDraft
            record.itemRequest = makeItemRequest(from: submittedDraft, locationID: storageLocationID)
            record.userReviewedAt = .now
            record.isLocked = true
            record.savedAt = .now
            try await persist(record)
        }
        guard let itemRequest = record.itemRequest, let reviewedAt = record.userReviewedAt else {
            throw AppValidationError("The saved submission is incomplete. Contact an administrator before retrying.")
        }
        let client = try api()
        if record.sessionID == nil {
            let session = try await client.createSession(.init(
                receivingLocationId: storageLocationID,
                receivedAt: record.receivedAt,
                sourceChannel: "walk_in",
                clientMutationId: record.sessionMutationID
            ))
            record.sessionID = session.id
            try await persist(record)
        }
        if record.itemID == nil {
            let item = try await client.createItem(sessionID: record.sessionID!, body: itemRequest, idempotencyKey: record.itemMutationID)
            record.itemID = item.id
            try await persist(record)
        }
        if let photo = record.draft.packagePhotoData {
            _ = try await client.uploadEvidence(
                itemID: record.itemID!,
                jpegData: photo,
                capturedAt: record.draft.packagePhotoCapturedAt ?? record.receivedAt,
                evidenceType: "date_label"
            )
        }
        for photo in record.draft.referencePhotos ?? [] {
            guard let jpegData = photo.jpegData else { throw AppValidationError("A saved package photo is missing. Restore the draft before retrying.") }
            _ = try await client.uploadEvidence(itemID: record.itemID!, jpegData: jpegData,
                                                capturedAt: photo.capturedAt, evidenceType: "package_photo")
        }
        let response = try await client.submitItem(
            itemID: record.itemID!,
            body: .init(userReviewedAt: reviewedAt, evidenceConflict: record.draft.labelEdited == true || !(record.draft.dietaryClaims ?? []).isEmpty || !(record.draft.otherLabelClaims ?? []).isEmpty),
            idempotencyKey: record.submitMutationID
        )
        try await draftStore.delete(id: record.id)
        savedDrafts.removeAll { $0.id == record.id }
        await loadDashboard()
        return response
    }

    private func newSavedDraft(_ draft: IntakeDraft) -> SavedIntakeDraft {
        let key = draft.id.uuidString
        return SavedIntakeDraft(
            draft: draft, organizationID: organizationID, locationID: locationID, userID: userID, userRole: userRole,
            sessionMutationID: "ios-session-\(key)", itemMutationID: "ios-item-\(key)", submitMutationID: "ios-submit-\(key)",
            receivedAt: .now, savedAt: .now
        )
    }

    private func verifyIdentity(for record: SavedIntakeDraft) throws {
        guard record.organizationID == organizationID, record.locationID == locationID,
              record.userID == userID, record.userRole == userRole else {
            throw AppValidationError("Switch Settings back to the identity and location used for this saved draft before submitting it.")
        }
    }

    private func persist(_ record: SavedIntakeDraft) async throws {
        try await draftStore.save(record)
        savedDrafts.removeAll { $0.id == record.id }
        savedDrafts.insert(record, at: 0)
        savedDrafts.sort { $0.savedAt > $1.savedAt }
        savedDraftsError = nil
    }

    private func makeItemRequest(from draft: IntakeDraft, locationID: UUID) -> CreateItemRequest {
        CreateItemRequest(
            productId: draft.identityEdited == true ? nil : draft.candidate?.productId,
            productName: draft.productName,
            brand: draft.brand.nilIfBlank,
            category: FoodCategory.from(raw: draft.category ?? draft.candidate?.category).rawValue,
            identitySource: draft.usedPhotoSuggestions == true ? "image" : draft.identityEdited == true || draft.scan?.normalizedGTIN == nil ? "manual" : identitySource(for: draft.scan?.scheme ?? .unknown),
            scannedCode: draft.scan?.raw.nilIfBlank,
            quantity: Decimal(draft.quantity),
            quantityUnit: draft.quantityUnit,
            dateType: draft.hasPrintedDate ? draft.dateType : "none",
            dateValue: draft.hasPrintedDate ? draft.dateValue.map(Self.dateFormatter.string(from:)) : nil,
            dateLabelRaw: draft.hasPrintedDate ? draft.dateLabelRaw.nilIfBlank : nil,
            storageType: draft.storageType,
            storageLocationId: locationID,
            packageCondition: draft.packageCondition,
            temperatureStatus: draft.temperatureStatus,
            calorieStatus: draft.calories == nil ? "not_labeled" : "recorded",
            calories: draft.calories.map { Decimal($0) },
            calorieBasis: draft.calorieBasis,
            servingSize: draft.servingSize?.nilIfBlank,
            dietaryClaims: draft.dietaryClaims ?? [],
            otherLabelClaims: draft.otherLabelClaims ?? [],
            allergens: acceptedAllergens(from: draft.allergenOverrides ?? draft.candidate?.allergens ?? []),
            requiredFieldConfidence: [draft.usedPhotoSuggestions == true ? 0.6 : draft.candidate?.confidence ?? 0.3, 1, draft.hasPrintedDate ? 1 : 0.5]
        )
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
