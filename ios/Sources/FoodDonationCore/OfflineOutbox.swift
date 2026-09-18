import Foundation

public struct PendingMutation: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let path: String
    public let method: String
    public let body: Data
    public let createdAt: Date
    public init(id: String = UUID().uuidString, path: String, method: String, body: Data, createdAt: Date = .now) {
        self.id = id; self.path = path; self.method = method; self.body = body; self.createdAt = createdAt
    }
}

public actor OfflineOutbox {
    private let fileURL: URL
    private var mutations: [PendingMutation]

    public init(fileURL: URL) throws {
        self.fileURL = fileURL
        if FileManager.default.fileExists(atPath: fileURL.path) {
            mutations = try JSONDecoder().decode([PendingMutation].self, from: Data(contentsOf: fileURL))
        } else { mutations = [] }
    }

    public func enqueue(_ mutation: PendingMutation) throws {
        guard !mutations.contains(where: { $0.id == mutation.id }) else { return }
        mutations.append(mutation); try persist()
    }

    public func pending() -> [PendingMutation] { mutations.sorted { $0.createdAt < $1.createdAt } }

    public func markApplied(id: String) throws { mutations.removeAll { $0.id == id }; try persist() }

    private func persist() throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(mutations).write(to: fileURL, options: .atomic)
    }
}
