import FoodDonationCore
import PhotosUI
import SwiftUI
import UIKit

struct IntakeReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: IntakeDraft
    @State private var isSubmitting = false
    @State private var isReadingPhoto = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showingCamera = false
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

                Section("Package date") {
                    if let data = draft.packagePhotoData, let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 180)
                            .accessibilityLabel("Selected package date photo")
                    }
                    HStack {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button("Take photo", systemImage: "camera") { showingCamera = true }
                        }
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            Label("Choose photo", systemImage: "photo")
                        }
                    }
                    .disabled(isReadingPhoto || isSubmitting)

                    if isReadingPhoto {
                        ProgressView("Reading printed date…")
                    }
                    Text("Aim at the printed date. OCR runs on this device; check the result against the package.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle("Package has a printed date", isOn: $draft.hasPrintedDate)
                        .onChange(of: draft.hasPrintedDate) { _, hasDate in
                            draft.dateConfirmed = false
                            if !hasDate {
                                draft.dateValue = nil
                                draft.dateLabelRaw = ""
                                draft.dateConfidence = nil
                                draft.dateSource = "Not captured"
                            }
                        }
                    if draft.hasPrintedDate {
                        Picker("Date type", selection: Binding(
                            get: { draft.dateType },
                            set: {
                                draft.dateType = $0
                                draft.dateConfirmed = false
                                if draft.dateSource == "Package photo" { draft.dateSource = "Photo, corrected" }
                            }
                        )) {
                            Text("Best if used by").tag("best_if_used_by")
                            Text("Best before").tag("best_before")
                            Text("Use by").tag("use_by")
                            Text("Expiration").tag("expiration")
                            Text("Sell by").tag("sell_by")
                            Text("Unknown").tag("unknown")
                        }
                        if draft.dateValue == nil {
                            Button("Set printed date") {
                                draft.dateValue = .now
                                draft.dateSource = "Manual entry"
                                draft.dateConfidence = nil
                            }
                        } else {
                            DatePicker("Date", selection: Binding(
                                get: { draft.dateValue ?? .now },
                                set: {
                                    draft.dateValue = $0
                                    draft.dateConfirmed = false
                                    if draft.dateSource == "Package photo" { draft.dateSource = "Photo, corrected" }
                                    draft.dateConfidence = nil
                                }
                            ), displayedComponents: .date)
                        }
                        TextField("Printed text (optional)", text: Binding(
                            get: { draft.dateLabelRaw },
                            set: {
                                draft.dateLabelRaw = $0
                                draft.dateConfirmed = false
                                if draft.dateSource == "Package photo" { draft.dateSource = "Photo, corrected" }
                            }
                        ))
                        LabeledContent("Source", value: draft.dateSource)
                        if let confidence = draft.dateConfidence {
                            LabeledContent("OCR confidence", value: confidence.formatted(.percent.precision(.fractionLength(0))))
                            if confidence < 0.9 {
                                Label("Low confidence — compare the date with the package or retake the photo.", systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                            }
                        }
                        if draft.dateValue != nil {
                            Button(draft.dateConfirmed ? "Date confirmed" : "Confirm date matches package") {
                                draft.dateConfirmed = true
                            }
                            .disabled(draft.dateConfirmed)
                        }
                    } else {
                        Label("No date will be invented. This item will be sent for review.", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                    .disabled(isSubmitting || isReadingPhoto || (draft.hasPrintedDate && !draft.dateConfirmed))
                }
            }
            .sheet(isPresented: $showingCamera) {
                PackagePhotoCamera { data in
                    Task { await readPhoto(data) }
                }
                .ignoresSafeArea()
            }
            .onChange(of: selectedPhoto) { _, photo in
                guard let photo else { return }
                Task {
                    defer { selectedPhoto = nil }
                    do {
                        guard let data = try await photo.loadTransferable(type: Data.self) else {
                            throw AppValidationError("Could not load the selected photo.")
                        }
                        await readPhoto(data)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
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

    private func readPhoto(_ data: Data) async {
        isReadingPhoto = true
        errorMessage = nil
        draft.packagePhotoData = data
        defer { isReadingPhoto = false }
        do {
            guard let match = try await PackageDateOCR.recognize(jpegData: data) else {
                draft.hasPrintedDate = false
                draft.dateValue = nil
                draft.dateConfirmed = false
                errorMessage = "No complete date was recognized. Retake the label photo or enter the date manually."
                return
            }
            draft.hasPrintedDate = true
            draft.dateValue = match.date
            draft.dateType = match.dateType
            draft.dateLabelRaw = match.rawText
            draft.dateSource = "Package photo"
            draft.dateConfidence = match.confidence
            draft.dateConfirmed = false
        } catch {
            errorMessage = "Could not read the photo: \(error.localizedDescription)"
        }
    }
}
