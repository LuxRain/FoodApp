import FoodDonationCore
import SwiftUI

struct IntakeReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: IntakeDraft
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    let submit: (IntakeDraft) async throws -> Void

    init(draft: IntakeDraft, submit: @escaping (IntakeDraft) async throws -> Void) {
        _draft = State(initialValue: draft)
        self.submit = submit
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Product") {
                    TextField("Product name", text: $draft.productName)
                    TextField("Brand", text: $draft.brand)
                    LabeledContent("Code", value: draft.candidate.normalizedCode)
                        .font(.system(.body, design: .monospaced))
                    LabeledContent("Source", value: sourceLabel)
                    LabeledContent("Confidence", value: draft.candidate.confidence.formatted(.percent.precision(.fractionLength(0))))
                }

                Section("Quantity") {
                    TextField("Quantity", value: $draft.quantity, format: .number)
                        .keyboardType(.decimalPad)
                    Picker("Unit", selection: $draft.quantityUnit) {
                        Text("Each").tag("each")
                        Text("Can").tag("can")
                        Text("Box").tag("box")
                        Text("Pound").tag("lb")
                    }
                }

                Section("Printed date") {
                    Toggle("Package has a printed date", isOn: $draft.hasPrintedDate)
                    if draft.hasPrintedDate {
                        Picker("Date type", selection: $draft.dateType) {
                            Text("Best if used by").tag("best_if_used_by")
                            Text("Best before").tag("best_before")
                            Text("Use by").tag("use_by")
                            Text("Expiration").tag("expiration")
                            Text("Sell by").tag("sell_by")
                        }
                        DatePicker("Date", selection: $draft.dateValue, displayedComponents: .date)
                        TextField("Printed text (optional)", text: $draft.dateLabelRaw)
                    }
                }

                Section("Storage and condition") {
                    Picker("Storage", selection: $draft.storageType) {
                        Text("Shelf stable").tag("shelf_stable")
                        Text("Refrigerated").tag("refrigerated")
                        Text("Frozen").tag("frozen")
                    }
                    Picker("Package", selection: $draft.packageCondition) {
                        Text("Acceptable").tag("acceptable")
                        Text("Damaged").tag("damaged")
                    }
                    Picker("Temperature", selection: $draft.temperatureStatus) {
                        Text("Not applicable").tag("not_applicable")
                        Text("Acceptable").tag("acceptable")
                        Text("Concern").tag("concern")
                    }
                }

                if draft.calories != nil || !draft.candidate.allergens.isEmpty {
                    Section("Label information") {
                        if let calories = draft.calories {
                            LabeledContent("Calories", value: calories.formatted())
                            LabeledContent("Basis", value: (draft.calorieBasis ?? "unknown").replacingOccurrences(of: "_", with: " "))
                        }
                        ForEach(draft.candidate.allergens, id: \.code) { allergen in
                            LabeledContent(allergen.code.replacingOccurrences(of: "_", with: " ").capitalized, value: allergen.declaration.replacingOccurrences(of: "_", with: " "))
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Verify donation")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isSubmitting)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSubmitting ? "Submitting" : "Submit") {
                        Task { await submitDraft() }
                    }
                    .disabled(isSubmitting)
                }
            }
        }
    }

    private var sourceLabel: String {
        draft.candidate.source.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func submitDraft() async {
        isSubmitting = true
        errorMessage = nil
        do {
            try await submit(draft)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isSubmitting = false
        }
    }
}
