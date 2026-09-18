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

        print("FoodDonationCore checks passed")
    }
}
