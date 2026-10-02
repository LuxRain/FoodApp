import FoodDonationCore
import SwiftUI

struct AdminReviewView: View {
    let model: AppModel

    var body: some View {
        Group {
            switch model.reviewQueueState {
            case .idle where model.reviewItems.isEmpty,
                 .loading where model.reviewItems.isEmpty:
                ProgressView("Loading review queue")
            case let .failed(message) where model.reviewItems.isEmpty:
                ContentUnavailableView {
                    Label("Cannot load review queue", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") { Task { await model.loadReviewQueue() } }
                        .buttonStyle(.borderedProminent)
                }
            default:
                List {
                    if model.reviewItems.isEmpty {
                        ContentUnavailableView("Nothing needs review", systemImage: "checkmark.seal", description: Text("Submitted exceptions will appear here."))
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(model.reviewItems) { item in
                            NavigationLink {
                                AdminReviewDetailView(item: item, model: model)
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(item.productName).font(.headline)
                                    Text("\(item.quantity.formatted()) \(item.quantityUnit) · \(item.status == .quarantined ? "Quarantined" : "Pending review")")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Text(item.routingReasonCodes.map(Self.label).joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
                .refreshable { await model.loadReviewQueue() }
            }
        }
        .task { await model.loadReviewQueue() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.loadReviewQueue() } }
            }
        }
    }

    static func label(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

private struct AdminReviewDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let item: AdminReviewItem
    let model: AppModel
    @State private var reason = ""
    @State private var pendingDecision: String?
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var lastAttemptedDecision: String?
    @FocusState private var reasonFocused: Bool

    var body: some View {
        Form {
            Section("Product") {
                LabeledContent("Name", value: item.productName)
                if let brand = item.brand { LabeledContent("Brand", value: brand) }
                if let code = item.scannedCode { LabeledContent("Scanned code", value: code) }
                LabeledContent("Identity", value: AdminReviewView.label(item.identitySource))
                LabeledContent("Quantity", value: "\(item.quantity.formatted()) \(item.quantityUnit)")
                LabeledContent("Submitted", value: item.createdAt.formatted(date: .abbreviated, time: .shortened))
            }

            Section("Safety and storage") {
                LabeledContent("Date", value: item.dateValue ?? "Not recorded")
                LabeledContent("Date type", value: AdminReviewView.label(item.dateType))
                if let printed = item.dateLabelRaw, !printed.isEmpty { LabeledContent("Printed text", value: printed) }
                LabeledContent("Storage", value: AdminReviewView.label(item.storageType))
                LabeledContent("Location", value: item.storageLocationName)
                LabeledContent("Package", value: AdminReviewView.label(item.packageCondition))
                LabeledContent("Temperature", value: AdminReviewView.label(item.temperatureStatus))
            }

            Section("Nutrition and allergens") {
                LabeledContent("Calories", value: item.calories.map { "\($0.formatted()) (\(AdminReviewView.label(item.calorieBasis ?? "unknown")))" } ?? AdminReviewView.label(item.calorieStatus))
                if item.allergens.isEmpty {
                    Text("No allergens recorded; this is not a verified allergen-free claim.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(item.allergens, id: \.code) { allergen in
                        LabeledContent(AdminReviewView.label(allergen.code), value: AdminReviewView.label(allergen.declaration))
                    }
                }
            }

            Section("Why review is needed") {
                ForEach(item.routingReasonCodes, id: \.self) { code in
                    Label(AdminReviewView.label(code), systemImage: "exclamationmark.triangle")
                }
            }

            Section {
                PackageEvidenceView(itemID: item.id, model: model)
            }

            Section("Decision") {
                TextField("Reason for decision", text: $reason, axis: .vertical)
                    .lineLimit(2...4)
                    .focused($reasonFocused)
                    .disabled(isSubmitting || lastAttemptedDecision != nil)
                Text("Check the package, date, storage conditions, and any photo before deciding. A reason is required and will be recorded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(item.status == .quarantined ? "Release to inventory" : "Accept into inventory") {
                    confirm("accept")
                }
                .disabled(decisionDisabled)
                if item.status != .quarantined {
                    Button("Quarantine") { confirm("quarantine") }
                        .tint(.orange)
                        .disabled(decisionDisabled)
                }
                Button("Reject", role: .destructive) { confirm("reject") }
                    .disabled(decisionDisabled)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                    Button("Retry decision") {
                        if let retryDecision { confirm(retryDecision) }
                    }
                        .disabled(retryDecision == nil)
                }
            }
        }
        .navigationTitle("Review donation")
        .navigationBarTitleDisplayMode(.inline)
        .alert(confirmationTitle, isPresented: Binding(
            get: { pendingDecision != nil },
            set: { if !$0 { pendingDecision = nil } }
        )) {
            if let decision = pendingDecision {
                Button(confirmationAction, role: decision == "reject" ? .destructive : nil) {
                    Task { await submit(decision) }
                }
            }
            Button("Cancel", role: .cancel) { pendingDecision = nil }
        } message: {
            Text("\(item.productName)\nReason: \(reason.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }

    private var retryDecision: String? {
        guard let errorMessage, !errorMessage.isEmpty else { return nil }
        return lastAttemptedDecision
    }

    private var decisionDisabled: Bool {
        isSubmitting || lastAttemptedDecision != nil || reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var confirmationTitle: String {
        switch pendingDecision {
        case "accept": item.status == .quarantined ? "Release into inventory?" : "Accept into inventory?"
        case "quarantine": "Quarantine this item?"
        case "reject": "Reject this item?"
        default: "Confirm decision?"
        }
    }

    private var confirmationAction: String {
        switch pendingDecision {
        case "accept": item.status == .quarantined ? "Release" : "Accept"
        case "quarantine": "Quarantine"
        case "reject": "Reject"
        default: "Confirm"
        }
    }

    private func confirm(_ decision: String) {
        reasonFocused = false
        pendingDecision = decision
    }

    private func submit(_ decision: String) async {
        isSubmitting = true
        pendingDecision = nil
        lastAttemptedDecision = decision
        errorMessage = nil
        do {
            _ = try await model.decide(item, decision: decision, reason: reason)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isSubmitting = false
        }
    }
}
