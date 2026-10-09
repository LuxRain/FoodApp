import SwiftUI

private enum SavedDraftAlert: Identifiable {
    case confirm(SavedIntakeDraft)
    case failure(String)

    var id: String {
        switch self {
        case .confirm(let record): "confirm-\(record.id.uuidString)"
        case .failure: "failure"
        }
    }
}

struct SavedDraftsView: View {
    let model: AppModel
    let openDraft: (IntakeDraft) -> Void
    @State private var activeAlert: SavedDraftAlert?

    var body: some View {
        List {
            if let error = model.savedDraftsError {
                Section {
                    Text(error).foregroundStyle(.red)
                    Button("Try loading again") { Task { await model.loadSavedDrafts() } }
                }
            }

            if model.savedDrafts.isEmpty && model.savedDraftsError == nil {
                ContentUnavailableView("No saved drafts", systemImage: "tray", description: Text("Use Save on this iPhone in the verification form to keep an item for later."))
                    .listRowBackground(Color.clear)
            } else {
                ForEach(model.savedDrafts) { record in
                    Button {
                        openDraft(record.draft)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: record.isLocked ? "arrow.clockwise.circle" : "square.and.pencil")
                                .font(.title2)
                                .foregroundStyle(record.isLocked ? .orange : .blue)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(record.draft.productName.isEmpty ? "Unnamed item" : record.draft.productName)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(record.isLocked ? "Submission pending · Tap to retry" : "Draft · Tap to edit")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text("Saved \(record.savedAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if record.draft.packagePhotoData != nil {
                                Image(systemName: "photo").foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button {
                            activeAlert = .confirm(record)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .tint(.red)
                    }
                }
            }
        }
        .refreshable { await model.loadSavedDrafts() }
        .alert(item: $activeAlert) { alert in
            switch alert {
            case .confirm(let record):
                let message = record.isLocked || record.sessionID != nil || record.itemID != nil
                    ? "Delete this saved copy and its photos from this iPhone? A submission may already exist on the server. This will not delete it, and you will lose the local retry."
                    : "Delete this unsent draft and its photos from this iPhone? This cannot be undone. No donation record will be deleted from the server."
                return Alert(
                    title: Text("Delete saved item?"),
                    message: Text(message),
                    primaryButton: .destructive(Text("Delete")) {
                        Task {
                            do { try await model.deleteSavedDraft(id: record.id) }
                            catch { activeAlert = .failure(error.localizedDescription) }
                        }
                    },
                    secondaryButton: .cancel()
                )
            case .failure(let message):
                return Alert(title: Text("Could not delete saved item"), message: Text(message), dismissButton: .default(Text("OK")))
            }
        }
    }
}
