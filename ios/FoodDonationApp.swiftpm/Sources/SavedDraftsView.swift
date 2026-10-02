import SwiftUI

struct SavedDraftsView: View {
    let model: AppModel
    let openDraft: (IntakeDraft) -> Void

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
                }
            }
        }
        .refreshable { await model.loadSavedDrafts() }
    }
}
