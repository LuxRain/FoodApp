import Foundation

public enum UserRole: String, Codable, Sendable { case regularUser = "regular_user"; case admin }
public enum DateUrgency: String, Codable, Sendable { case expiredOrPast = "expired_or_past"; case dueSoon = "due_soon"; case good; case noDate = "no_date" }
public enum IntakeStatus: String, Codable, Sendable { case draft, capturing, readyForUserReview = "ready_for_user_review", submitted, processing, processingFailed = "processing_failed", autoAccepted = "auto_accepted", pendingAdminReview = "pending_admin_review", adminAccepted = "admin_accepted", quarantined, rejected }

public struct AuthContext: Sendable {
    public let userID: String
    public let organizationID: String
    public let role: UserRole
    public init(userID: String, organizationID: String, role: UserRole) {
        self.userID = userID; self.organizationID = organizationID; self.role = role
    }
}

public struct CreateSessionRequest: Codable, Sendable {
    public let receivingLocationId: UUID
    public let receivedAt: Date
    public let sourceChannel: String?
    public let clientMutationId: String
    public init(receivingLocationId: UUID, receivedAt: Date, sourceChannel: String?, clientMutationId: String) {
        self.receivingLocationId = receivingLocationId; self.receivedAt = receivedAt; self.sourceChannel = sourceChannel; self.clientMutationId = clientMutationId
    }
}

public struct IntakeSessionResponse: Codable, Sendable { public let id: UUID; public let status: String }

public struct AllergenDeclaration: Codable, Equatable, Sendable {
    public let code: String
    public let declaration: String
    public let labelText: String?
    public init(code: String, declaration: String, labelText: String? = nil) { self.code = code; self.declaration = declaration; self.labelText = labelText }
}

public struct CreateItemRequest: Codable, Sendable {
    public let productId: UUID?
    public let productName: String
    public let brand: String?
    public let identitySource: String
    public let quantity: Decimal
    public let quantityUnit: String
    public let dateType: String
    public let dateValue: String?
    public let dateLabelRaw: String?
    public let storageType: String
    public let storageLocationId: UUID
    public let packageCondition: String
    public let temperatureStatus: String
    public let calorieStatus: String
    public let calories: Decimal?
    public let calorieBasis: String?
    public let allergens: [AllergenDeclaration]
    public let requiredFieldConfidence: [Double]
}

public struct IntakeItemResponse: Codable, Sendable { public let id: UUID; public let status: IntakeStatus; public let version: Int }

public struct SubmitItemRequest: Codable, Sendable {
    public let userReviewedAt: Date
    public let allergenConflict: Bool
    public let evidenceConflict: Bool
    public let duplicateSuspected: Bool
    public init(userReviewedAt: Date, allergenConflict: Bool = false, evidenceConflict: Bool = false, duplicateSuspected: Bool = false) {
        self.userReviewedAt = userReviewedAt; self.allergenConflict = allergenConflict; self.evidenceConflict = evidenceConflict; self.duplicateSuspected = duplicateSuspected
    }
}

public struct SubmitItemResponse: Codable, Sendable {
    public let intakeItemId: UUID
    public let status: IntakeStatus
    public let routingReasonCodes: [String]
    public let inventoryLotId: UUID?
}

public struct DonationDashboardResponse: Codable, Sendable {
    public let items: [DonationDashboardItem]
    public let nextCursor: String?
}

public struct DonationDashboardItem: Codable, Identifiable, Sendable {
    public let intakeItemId: UUID
    public let inventoryLotId: UUID?
    public let product: ProductSummary
    public let onHand: QuantitySummary
    public let date: DateSummary
    public let nutritionTier: String
    public let location: LocationSummary
    public let inventoryState: String?
    public let intakeStatus: IntakeStatus
    public let acceptancePath: String?
    public let receivedAt: Date
    public var id: UUID { intakeItemId }
}

public struct ProductSummary: Codable, Sendable { public let name: String; public let brand: String? }
public struct QuantitySummary: Codable, Sendable { public let quantity: Double; public let unit: String }
public struct DateSummary: Codable, Sendable { public let type: String; public let value: String?; public let daysRemaining: Int?; public let urgency: DateUrgency }
public struct LocationSummary: Codable, Sendable { public let id: UUID; public let name: String }
