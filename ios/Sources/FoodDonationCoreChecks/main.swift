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
        precondition(FoodCategory.from(raw: "canned_beans") == .cannedJarred)
        precondition(FoodCategory.from(raw: "Smoked salmons") == .meatSeafood)
        precondition(FoodCategory.meatSeafood.symbol == "fish")
        precondition(FoodCategory.from(raw: nil) == .other)

        let labeledDate = DateLabelParser.bestMatch(in: [
            (text: "LOT 4827", confidence: 0.99),
            (text: "BEST BY", confidence: 0.97),
            (text: "Oct 14, 2026", confidence: 0.96),
        ])
        precondition(labeledDate?.dateType == "best_before")
        precondition(labeledDate?.rawText == "BEST BY Oct 14, 2026")
        precondition((labeledDate?.confidence ?? 0) > 0.9)

        let ambiguousDate = DateLabelParser.bestMatch(in: [(text: "10/14/26", confidence: 0.95)])
        precondition(ambiguousDate?.dateType == "unknown")
        precondition((ambiguousDate?.confidence ?? 1) < 0.9)
        if let date = ambiguousDate?.date {
            precondition(Calendar(identifier: .gregorian).component(.year, from: date) == 2026)
        }
        let preferredLabel = DateLabelParser.bestMatch(in: [
            (text: "2026-10-15", confidence: 1),
            (text: "USE BY 10/14/26", confidence: 0.95),
        ])
        precondition(preferredLabel?.dateType == "use_by")
        precondition(DateLabelParser.bestMatch(in: [(text: "BEST BY 10/14", confidence: 0.99)]) == nil)

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
        ), idempotencyKey: "swift-item-\(runID)")
        let testJPEG = Data(base64Encoded: "/9j/4AAQSkZJRgABAgAAAQABAAD//gAQTGF2YzYyLjExLjEwMAD/2wBDAAgKCgsKCw0NDQ0NDRAPEBAQEBAQEBAQEBASEhIVFRUSEhIQEBISFBQVFRcXFxUVFRUXFxkZGR4eHBwjIyQrKzP/xABMAAEBAAAAAAAAAAAAAAAAAAAABgEBAQAAAAAAAAAAAAAAAAAABgcQAQAAAAAAAAAAAAAAAAAAAAARAQAAAAAAAAAAAAAAAAAAAAD/wAARCAAQABADASIAAhEAAxEA/9oADAMBAAIRAxEAPwCtAR06f//Z")!
        let uploaded = try await api.uploadEvidence(itemID: item.id, jpegData: testJPEG, capturedAt: .now, evidenceType: "date_label")
        precondition(uploaded.intakeItemId == item.id)
        let evidence = try await api.evidence(itemID: item.id)
        precondition(evidence.items.contains { $0.id == uploaded.id })
        let downloaded = try await api.evidenceImage(itemID: item.id, evidenceID: uploaded.id)
        precondition(downloaded == testJPEG)
        let result = try await api.submitItem(
            itemID: item.id,
            body: .init(userReviewedAt: .now),
            idempotencyKey: "swift-submit-\(runID)"
        )
        precondition(result.status == .autoAccepted)
        precondition(result.inventoryLotId != nil)
        let dashboard = try await api.donationItems()
        precondition(dashboard.items.contains { $0.intakeItemId == item.id })

        let manualItem = try await api.createItem(sessionID: session.id, body: .init(
            productId: nil,
            productName: "Swift Manual Product \(runID)",
            brand: nil,
            identitySource: "manual",
            scannedCode: "unverified-code",
            quantity: 1,
            quantityUnit: "each",
            dateType: "none",
            dateValue: nil,
            dateLabelRaw: nil,
            storageType: "shelf_stable",
            storageLocationId: locationID,
            packageCondition: "acceptable",
            temperatureStatus: "not_applicable",
            calorieStatus: "not_labeled",
            calories: nil,
            calorieBasis: nil,
            allergens: [],
            requiredFieldConfidence: [0.3, 1, 0.5]
        ), idempotencyKey: "swift-manual-item-\(runID)")
        let manualSubmission = try await api.submitItem(
            itemID: manualItem.id,
            body: .init(userReviewedAt: .now),
            idempotencyKey: "swift-manual-submit-\(runID)"
        )
        precondition(manualSubmission.status == .pendingAdminReview)
        let adminAPI = FoodDonationAPI(
            baseURL: URL(string: baseURL)!,
            auth: .init(userID: "admin-demo", organizationID: organizationID, role: .admin)
        )
        let reviewQueue = try await adminAPI.adminReviewQueue()
        let reviewItem = reviewQueue.items.first { $0.id == manualItem.id }
        precondition(reviewItem?.scannedCode == "unverified-code")
        precondition(reviewItem?.packageCondition == "acceptable")
        let decision = try await adminAPI.decideIntakeItem(
            itemID: manualItem.id,
            body: .init(decision: "accept", reason: "Verified in Swift integration check"),
            idempotencyKey: "swift-manual-decision-\(runID)"
        )
        precondition(decision.status == .adminAccepted)
        precondition(decision.inventoryLotId != nil)
    }
}
