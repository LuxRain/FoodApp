import Foundation
import FoodDonationCore

@main
struct FoodDonationCoreChecks {
    static func main() async throws {
        let upc = ScanParser.parse("012345678905")
        precondition(upc.scheme == .upcA)
        precondition(upc.normalizedGTIN == "00012345678905")

        let gs1 = ScanParser.parse("]C1010001234567890515261014")
        precondition(gs1.normalizedGTIN == "00012345678905")
        precondition(gs1.dateYYMMDD == "261014")

        let lookupData = Data(#"{"candidates":[{"productId":"00000000-0000-4000-8000-000000000201","normalizedCode":"00012345678905","name":"Low-Sodium Black Beans","brand":"Community Pantry","category":"canned_beans","calories":110,"calorieBasis":"per_serving","servingSize":"130 g","allergens":[],"source":"internal_catalog","confidence":1,"requiresUserConfirmation":false}]}"#.utf8)
        let lookup = try JSONDecoder().decode(ProductLookupResponse.self, from: lookupData)
        precondition(lookup.candidates.first?.name == "Low-Sodium Black Beans")
        precondition(lookup.candidates.first?.productId?.uuidString == "00000000-0000-4000-8000-000000000201")

        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let outbox = try OfflineOutbox(fileURL: directory.appending(path: "outbox.json"))
        let mutation = PendingMutation(id: "check-1", path: "v1/intake-sessions", method: "POST", body: Data("{}".utf8))
        try await outbox.enqueue(mutation)
        try await outbox.enqueue(mutation)
        let pendingBeforeApply = await outbox.pending()
        precondition(pendingBeforeApply.count == 1)
        try await outbox.markApplied(id: mutation.id)
        let pendingAfterApply = await outbox.pending()
        precondition(pendingAfterApply.isEmpty)

        if let apiURL = ProcessInfo.processInfo.environment["FOOD_DONATION_API_URL"] {
            try await runAPIIntegration(baseURL: apiURL)
        }

        print("FoodDonationCore checks passed")
    }

    private static func runAPIIntegration(baseURL: String) async throws {
        let organizationID = "00000000-0000-4000-8000-000000000001"
        let locationID = UUID(uuidString: "00000000-0000-4000-8000-000000000101")!
        let api = FoodDonationAPI(
            baseURL: URL(string: baseURL)!,
            auth: .init(userID: "regular-demo", organizationID: organizationID, role: .regularUser)
        )
        let lookup = try await api.lookupProduct(.init(rawCode: "012345678905", scheme: .upcA))
        guard let candidate = lookup.candidates.first, candidate.productId != nil else {
            preconditionFailure("Development product lookup failed")
        }
        let runID = UUID().uuidString
        let session = try await api.createSession(.init(
            receivingLocationId: locationID,
            receivedAt: .now,
            sourceChannel: "swift_integration",
            clientMutationId: "swift-session-\(runID)"
        ))
        let date = Calendar.current.date(byAdding: .day, value: 30, to: .now)!
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        let item = try await api.createItem(sessionID: session.id, body: .init(
            productId: candidate.productId,
            productName: candidate.name,
            brand: candidate.brand,
            identitySource: "barcode",
            quantity: 1,
            quantityUnit: "can",
            dateType: "best_if_used_by",
            dateValue: formatter.string(from: date),
            dateLabelRaw: nil,
            storageType: "shelf_stable",
            storageLocationId: locationID,
            packageCondition: "acceptable",
            temperatureStatus: "not_applicable",
            calorieStatus: "not_labeled",
            calories: nil,
            calorieBasis: nil,
            allergens: [],
            requiredFieldConfidence: [1, 1, 1]
        ))
        let result = try await api.submitItem(
            itemID: item.id,
            body: .init(userReviewedAt: .now),
            idempotencyKey: "swift-submit-\(runID)"
        )
        precondition(result.status == .autoAccepted)
        precondition(result.inventoryLotId != nil)
        let dashboard = try await api.donationItems()
        precondition(dashboard.items.contains { $0.intakeItemId == item.id })
    }
}
