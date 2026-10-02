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
    var photoFileNames: [String: String]?

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
        let metadataURL = folder.appending(path: "draft.json")
        let previous = (try? Data(contentsOf: metadataURL)).flatMap { try? JSONDecoder().decode(SavedIntakeDraft.self, from: $0) }

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

        var photoFileNames: [String: String] = [:]
        metadata.draft.referencePhotos = try (record.draft.referencePhotos ?? []).map { photo in
            guard let jpegData = photo.jpegData else { throw CocoaError(.fileReadCorruptFile) }
            let hash = SHA256.hash(data: jpegData).map { String(format: "%02x", $0) }.joined()
            let fileName = "\(hash).jpg"
            let photoURL = folder.appending(path: fileName)
            if !FileManager.default.fileExists(atPath: photoURL.path) {
                try jpegData.write(to: photoURL, options: protectedWrite)
            }
            photoFileNames[photo.id.uuidString] = fileName
            var storedPhoto = photo
            storedPhoto.jpegData = nil
            return storedPhoto
        }
        metadata.photoFileNames = photoFileNames

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        try encoder.encode(metadata).write(to: metadataURL, options: protectedWrite)

        let oldFiles = Set([previous?.photoFileName].compactMap { $0 } + Array(previous?.photoFileNames?.values ?? [:].values))
        let currentFiles = Set([metadata.photoFileName].compactMap { $0 } + Array(photoFileNames.values))
        for fileName in oldFiles.subtracting(currentFiles) where Self.validPhotoFileName(fileName) {
            try? FileManager.default.removeItem(at: folder.appending(path: fileName))
        }
    }

    func loadAll() throws -> [SavedIntakeDraft] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let folders = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey])
        return try folders.filter { (try $0.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true }
            .map { folder in
                let data = try Data(contentsOf: folder.appending(path: "draft.json"))
                var record = try JSONDecoder().decode(SavedIntakeDraft.self, from: data)
                if let photoFileName = record.photoFileName {
                    guard Self.validPhotoFileName(photoFileName) else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    record.draft.packagePhotoData = try Data(contentsOf: folder.appending(path: photoFileName))
                }
                record.draft.referencePhotos = try (record.draft.referencePhotos ?? []).map { photo in
                    guard let fileName = record.photoFileNames?[photo.id.uuidString], Self.validPhotoFileName(fileName) else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    var loadedPhoto = photo
                    loadedPhoto.jpegData = try Data(contentsOf: folder.appending(path: fileName))
                    return loadedPhoto
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

    private static func validPhotoFileName(_ fileName: String) -> Bool {
        fileName.count == 68 && fileName.hasSuffix(".jpg") && fileName.dropLast(4).allSatisfy(\.isHexDigit)
    }
}
