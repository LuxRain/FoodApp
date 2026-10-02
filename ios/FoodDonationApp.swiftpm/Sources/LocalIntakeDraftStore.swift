import CryptoKit
import FoodDonationCore
import Foundation

struct SavedIntakeDraft: Codable, Identifiable, Sendable {
    var draft: IntakeDraft
    let organizationID: String
    let locationID: String
    let userID: String
    let userRole: UserRole
    let sessionMutationID: String
    let itemMutationID: String
    let submitMutationID: String
    let receivedAt: Date
    var userReviewedAt: Date?
    var itemRequest: CreateItemRequest?
    var sessionID: UUID?
    var itemID: UUID?
    var isLocked = false
    var savedAt: Date
    var photoFileName: String?

    var id: UUID { draft.id }
}

actor LocalIntakeDraftStore {
    private let directory: URL
    private let protectedWrite: Data.WritingOptions = [.atomic, .completeFileProtection]

    init(directory: URL) {
        self.directory = directory
    }

    func save(_ record: SavedIntakeDraft) throws {
        let folder = directory.appending(path: record.id.uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        var metadata = record
        let photo = metadata.draft.packagePhotoData
        metadata.draft.packagePhotoData = nil
        if let photo {
            let hash = SHA256.hash(data: photo).map { String(format: "%02x", $0) }.joined()
            metadata.photoFileName = "\(hash).jpg"
            let photoURL = folder.appending(path: metadata.photoFileName!)
            if !FileManager.default.fileExists(atPath: photoURL.path) {
                try photo.write(to: photoURL, options: protectedWrite)
            }
        } else {
            metadata.photoFileName = nil
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        try encoder.encode(metadata).write(to: folder.appending(path: "draft.json"), options: protectedWrite)
    }

    func loadAll() throws -> [SavedIntakeDraft] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let folders = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey])
        return try folders.filter { (try $0.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true }
            .map { folder in
                let data = try Data(contentsOf: folder.appending(path: "draft.json"))
                var record = try JSONDecoder().decode(SavedIntakeDraft.self, from: data)
                if let photoFileName = record.photoFileName {
                    guard photoFileName.count == 68,
                          photoFileName.hasSuffix(".jpg"),
                          photoFileName.dropLast(4).allSatisfy({ $0.isHexDigit }) else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    record.draft.packagePhotoData = try Data(contentsOf: folder.appending(path: photoFileName))
                }
                return record
            }
            .sorted { $0.savedAt > $1.savedAt }
    }

    func delete(id: UUID) throws {
        let folder = directory.appending(path: id.uuidString, directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.removeItem(at: folder)
        }
    }
}
