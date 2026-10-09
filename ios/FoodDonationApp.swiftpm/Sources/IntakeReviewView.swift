import FoodDonationCore
import PhotosUI
import SwiftUI
import UIKit

private enum IntakeEditField: Hashable {
    case productName, brand, category, quantity, unit, hasPrintedDate, dateType, date
    case storage, packageCondition, temperature, calories, calorieBasis, servingSize
    case allergen(String)
}

private enum LabelClaimCatalog {
    static let groups: [(title: String, codes: [String])] = [
        ("Free from", ["dairy_free", "lactose_free", "gluten_free", "wheat_free", "egg_free", "soy_free", "peanut_free", "tree_nut_free", "sesame_free", "fish_free", "shellfish_free"]),
        ("Dietary style", ["vegan", "vegetarian", "plant_based", "keto", "paleo"]),
        ("Nutrition", ["no_added_sugar", "sugar_free", "low_sugar", "low_sodium", "no_salt_added", "low_fat", "fat_free", "low_calorie", "high_protein", "high_fiber"]),
        ("Sourcing and religious", ["kosher", "halal", "organic", "non_gmo"]),
    ]
}

struct IntakeReviewView: View {
    private static let dateTimeZone = TimeZone(secondsFromGMT: 0)!
    private static let dateDisplayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = .current
        formatter.timeZone = dateTimeZone
        formatter.dateStyle = .medium
        return formatter
    }()

    @Environment(\.dismiss) private var dismiss
    @State private var draft: IntakeDraft
    @State private var isSubmitting = false
    @State private var isSaving = false
    @State private var isLocked: Bool
    @State private var isReadingPhoto = false
    @State private var isAddingPhotos = false
    @State private var isAnalyzing = false
    @State private var analysis: PhotoAnalysisResponse?
    @State private var otherClaimInput = ""
    @State private var editingField: IntakeEditField?
    @State private var selectedPackagePhotos: [PhotosPickerItem] = []
    @State private var showingPackageCamera = false
    @State private var previewPhoto: IntakePhoto?
    @State private var errorMessage: String?
    @State private var showingSubmissionAlert = false
    @State private var submissionAlertTitle = ""
    @State private var submissionAlertMessage = ""
    let submit: (IntakeDraft) async throws -> Void
    let save: (IntakeDraft) async throws -> Void
    let analyze: ([Data]) async throws -> PhotoAnalysisResponse
    let isLockedAfterFailure: (UUID) -> Bool

    init(draft: IntakeDraft, initiallyLocked: Bool, submit: @escaping (IntakeDraft) async throws -> Void,
         save: @escaping (IntakeDraft) async throws -> Void,
         analyze: @escaping ([Data]) async throws -> PhotoAnalysisResponse,
         isLockedAfterFailure: @escaping (UUID) -> Bool) {
        _draft = State(initialValue: draft)
        _isLocked = State(initialValue: initiallyLocked)
        self.submit = submit
        self.save = save
        self.analyze = analyze
        self.isLockedAfterFailure = isLockedAfterFailure
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Submission status") {
                    if let activity = submissionActivityHint {
                        Label(activity, systemImage: "clock")
                            .foregroundStyle(.secondary)
                    } else if draft.submissionIssues.isEmpty {
                        Label(isLocked ? "Ready to retry. Tap Retry in the upper-right." : "Ready to submit. Tap Submit in the upper-right.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        ForEach(draft.submissionIssues, id: \.self) { issue in
                            Label(issue, systemImage: "exclamationmark.circle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                }
                if isLocked {
                    Section {
                        Label("Saved on this iPhone. Details are locked while submission is pending; retry when the server is available.", systemImage: "tray.full")
                            .foregroundStyle(.orange)
                    }
                }
                Section("Package photos and date (\(photoCount)/8)") {
                        Text(draft.candidate == nil
                             ? "Photograph one package: front, ingredients, allergens, weight, and printed date. AI can suggest details, which you must verify."
                             : "Add a clear photo of the printed date, then tap Read date below that photo. Photos are optional if you enter the date manually.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !previewPhotos.isEmpty {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                                ForEach(previewPhotos) { photo in
                                    if let data = photo.jpegData, let image = UIImage(data: data) {
                                        VStack(spacing: 4) {
                                            ZStack(alignment: .topTrailing) {
                                                Button {
                                                    previewPhoto = photo
                                                } label: {
                                                    Image(uiImage: image)
                                                        .resizable()
                                                        .scaledToFill()
                                                        .frame(height: 96)
                                                        .frame(maxWidth: .infinity)
                                                        .clipped()
                                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                                }
                                                .buttonStyle(.borderless)
                                                .accessibilityLabel("Preview package photo")
                                                Button {
                                                    if photo.id == draft.id {
                                                        removeDatePhoto()
                                                    } else {
                                                        draft.referencePhotos?.removeAll { $0.id == photo.id }
                                                        invalidateAnalysis()
                                                    }
                                                } label: {
                                                    Image(systemName: "xmark.circle.fill")
                                                        .font(.title2)
                                                        .foregroundStyle(.white)
                                                        .shadow(color: .black.opacity(0.8), radius: 2)
                                                        .frame(width: 44, height: 44)
                                                }
                                                .buttonStyle(.borderless)
                                                .accessibilityLabel("Remove package photo")
                                                .disabled(isAddingPhotos || isReadingPhoto || isAnalyzing || isSubmitting)
                                            }
                                            if photo.id == draft.id {
                                                Label("Date label", systemImage: "calendar.badge.checkmark")
                                                    .font(.caption.weight(.semibold))
                                                    .foregroundStyle(.green)
                                                    .frame(minHeight: 44)
                                            } else {
                                                Button {
                                                    Task { await selectDatePhoto(photo) }
                                                } label: {
                                                    Label("Read date", systemImage: "calendar")
                                                        .font(.caption.weight(.semibold))
                                                        .frame(maxWidth: .infinity, minHeight: 44)
                                                }
                                                .buttonStyle(.borderless)
                                                .disabled(isAddingPhotos || isReadingPhoto || isAnalyzing || isSubmitting)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        HStack(spacing: 12) {
                            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                                Button { showingPackageCamera = true } label: {
                                    Label("Take photo", systemImage: "camera")
                                        .frame(maxWidth: .infinity, minHeight: 48)
                                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Take package photo with camera")
                            }
                            PhotosPicker(selection: $selectedPackagePhotos, maxSelectionCount: max(1, 8 - photoCount), matching: .images) {
                                Label("Photo library", systemImage: "photo.on.rectangle")
                                    .frame(maxWidth: .infinity, minHeight: 48)
                                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Choose package photos from library")
                        }
                        .font(.subheadline.weight(.semibold))
                        .disabled(photoCount >= 8 || isAddingPhotos || isReadingPhoto || isAnalyzing || isSubmitting)
                        if isAddingPhotos { ProgressView("Adding photos…") }
                        if draft.candidate == nil {
                            Button {
                                Task { await analyzePackagePhotos() }
                            } label: {
                                Label("Analyze photos with AI", systemImage: "sparkles")
                                    .frame(maxWidth: .infinity, minHeight: 48)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(photoCount == 0 || isAddingPhotos || isReadingPhoto || isAnalyzing || isSubmitting)
                            if isAnalyzing { ProgressView("Reading package photos… This may take a minute.") }
                        }
                        if draft.candidate == nil, let analysis {
                            Text("AI suggestions — compare with the physical package before using. Missing means not visible, not absent.")
                                .font(.caption).foregroundStyle(.orange)
                            if let value = analysis.productName { LabeledContent("Product", value: value) }
                            if let value = analysis.brand { LabeledContent("Brand", value: value) }
                            if let value = analysis.ingredients { LabeledContent("Ingredients", value: value) }
                            if let value = analysis.allergens { LabeledContent("Allergen text", value: value) }
                            if let value = analysis.packageWeight { LabeledContent("Weight", value: value) }
                            if let value = analysis.calories { LabeledContent("Calories", value: value.formatted()) }
                            if let value = analysis.servingSize { LabeledContent("Serving size", value: value) }
                            if !analysis.dietaryClaims.isEmpty {
                                LabeledContent("Label claims", value: analysis.dietaryClaims.map(displayLabel).joined(separator: ", "))
                            }
                            if !analysis.otherLabelClaims.isEmpty {
                                LabeledContent("Other printed claims", value: analysis.otherLabelClaims.joined(separator: ", "))
                            }
                            Button("Apply product and brand suggestions") { applyPhotoSuggestions(analysis) }
                                .disabled(analysis.productName == nil && analysis.brand == nil)
                            Text("AI text for ingredients, allergens, and weight is shown for comparison only. Printed date text appears once below; check the actual date and confirm it separately.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Text("Printed date")
                            .font(.headline)
                    if isReadingPhoto {
                        ProgressView("Reading printed date…")
                    }
                    Text("Tap Read date below a photo for OCR, or enter the printed date manually. Confirm the actual date against the package before submitting.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    editableRow("Package has a printed date", value: draft.hasPrintedDate ? "Yes" : "No", field: .hasPrintedDate) {
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
                    }
                    if draft.hasPrintedDate {
                        editableRow("Date type", value: dateTypeLabel, field: .dateType, highlight: !draft.dateConfirmed) {
                            Picker("Date type", selection: Binding(
                                get: { draft.dateType },
                                set: {
                                    draft.dateType = $0
                                    draft.dateConfirmed = false
                                    if draft.dateSource == "Package photo" || draft.dateSource == "AI suggestion · unverified" {
                                        draft.dateSource = "Photo, corrected"
                                    }
                                }
                            )) {
                                Text("Best if used by").tag("best_if_used_by")
                                Text("Best before").tag("best_before")
                                Text("Use by").tag("use_by")
                                Text("Expiration").tag("expiration")
                                Text("Sell by").tag("sell_by")
                                Text("Unknown").tag("unknown")
                            }
                            .pickerStyle(.menu)
                        }
                        editableRow("Date", value: draft.dateValue.map(Self.dateDisplayFormatter.string(from:)) ?? "Not set", field: .date,
                                    highlight: !draft.dateConfirmed) {
                            DatePicker("Date", selection: Binding(
                                get: { draft.dateValue ?? .now },
                                set: {
                                    let wasUnset = draft.dateValue == nil
                                    draft.dateValue = $0
                                    draft.dateConfirmed = false
                                    if draft.dateSource == "Package photo" || draft.dateSource == "Photo, corrected" || draft.dateSource == "AI suggestion · unverified" {
                                        draft.dateSource = "Photo, corrected"
                                    } else if wasUnset {
                                        draft.dateSource = "Manual entry"
                                    }
                                    draft.dateConfidence = nil
                                }
                            ), displayedComponents: .date)
                                .environment(\.timeZone, Self.dateTimeZone)
                            if draft.dateValue == nil {
                                Button("Use selected date") {
                                    draft.dateValue = .now
                                    draft.dateConfirmed = false
                                    draft.dateSource = "Manual entry"
                                    draft.dateConfidence = nil
                                }
                            }
                        }
                        if !draft.dateConfirmed {
                            Label(draft.dateValue == nil
                                  ? (draft.dateLabelRaw.isEmpty
                                     ? "Set the date shown on the package, then confirm it."
                                     : "The label text was captured, but no complete date was recognized. Set the date from the package, then confirm it.")
                                  : "Suggested date and type — compare them with the package, correct them if needed, then turn on the confirmation switch.",
                                  systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        if draft.dateType == "unknown" {
                            Text("Date type was not identified. If the package says Best By, Use By, Expiration, or Sell By, choose it with the pencil; otherwise leave Unknown.")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        if !draft.dateLabelRaw.isEmpty {
                            Text("Captured label text: \(draft.dateLabelRaw)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Captured label text, \(draft.dateLabelRaw)")
                        }
                        LabeledContent("Source", value: draft.dateSource)
                        if let confidence = draft.dateConfidence {
                            LabeledContent("OCR confidence", value: confidence.formatted(.percent.precision(.fractionLength(0))))
                            if confidence < 0.9 {
                                Label("Low confidence — compare the date with the package or retake the photo.", systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                            }
                        }
                        if draft.dateValue != nil {
                            Toggle("I checked the date and type on the package", isOn: $draft.dateConfirmed)
                        }
                    } else {
                        Label("No date will be invented. This item will be sent for review.", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Product") {
                    editableRow("Product name", value: draft.productName, field: .productName) {
                        TextField("Product name", text: Binding(
                            get: { draft.productName },
                            set: { newValue in
                                if draft.candidate != nil && newValue != draft.productName { draft.identityEdited = true }
                                draft.productName = newValue
                            }
                        ))
                            .textInputAutocapitalization(.words)
                    }
                    editableRow("Brand", value: draft.brand, field: .brand) {
                        TextField("Brand", text: Binding(
                            get: { draft.brand },
                            set: { newValue in
                                if draft.candidate != nil && newValue != draft.brand { draft.identityEdited = true }
                                draft.brand = newValue
                            }
                        ))
                    }
                    editableRow("Category", value: FoodCategory.from(raw: draft.category ?? draft.candidate?.category).title, field: .category) {
                        Picker("Category", selection: Binding(
                            get: { FoodCategory.from(raw: draft.category ?? draft.candidate?.category).rawValue },
                            set: { newValue in
                                if draft.candidate != nil && newValue != FoodCategory.from(raw: draft.category ?? draft.candidate?.category).rawValue {
                                    draft.identityEdited = true
                                }
                                draft.category = newValue
                            }
                        )) {
                            ForEach(FoodCategory.allCases) { category in
                                Text(category.title).tag(category.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    if let code = draft.scan?.raw, !code.isEmpty {
                        LabeledContent("Scanned code", value: code)
                            .font(.system(.body, design: .monospaced))
                    }
                    LabeledContent("Source", value: draft.usedPhotoSuggestions == true ? "Photo analysis · verify" : sourceLabel)
                    if draft.identityEdited == true {
                        Label("Edited catalog identity — an admin will review this item before it enters inventory.", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if let candidate = draft.candidate {
                        LabeledContent("Confidence", value: candidate.confidence.formatted(.percent.precision(.fractionLength(0))))
                    } else {
                        Label("No catalog match. Add package photos and confirm what you can; an admin will review this item before it enters inventory.", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Text("Scanned code, source, and confidence are read-only evidence. Use the pencils above to correct the donation record.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Quantity") {
                    editableRow("Quantity", value: draft.quantity.formatted(), field: .quantity) {
                        TextField("Quantity", value: $draft.quantity, format: .number)
                            .keyboardType(.decimalPad)
                    }
                    editableRow("Unit", value: unitLabel, field: .unit) {
                        Picker("Unit", selection: $draft.quantityUnit) {
                            Text("Each").tag("each")
                            Text("Can").tag("can")
                            Text("Box").tag("box")
                            Text("Pound").tag("lb")
                        }
                        .pickerStyle(.menu)
                    }
                }

                Section("Storage and condition") {
                    editableRow("Storage", value: displayLabel(draft.storageType), field: .storage) {
                        Picker("Storage", selection: $draft.storageType) {
                            Text("Shelf stable").tag("shelf_stable")
                            Text("Refrigerated").tag("refrigerated")
                            Text("Frozen").tag("frozen")
                        }
                        .pickerStyle(.menu)
                    }
                    editableRow("Package", value: displayLabel(draft.packageCondition), field: .packageCondition) {
                        Picker("Package", selection: $draft.packageCondition) {
                            Text("Acceptable").tag("acceptable")
                            Text("Damaged").tag("damaged")
                        }
                        .pickerStyle(.menu)
                    }
                    editableRow("Temperature", value: displayLabel(draft.temperatureStatus), field: .temperature) {
                        Picker("Temperature", selection: $draft.temperatureStatus) {
                            Text("Not applicable").tag("not_applicable")
                            Text("Acceptable").tag("acceptable")
                            Text("Concern").tag("concern")
                        }
                        .pickerStyle(.menu)
                    }
                }

                Section("Label information") {
                    editableRow("Calories", value: draft.calories.map { $0.formatted() } ?? "Not recorded", field: .calories) {
                        TextField("Calories", value: Binding(
                            get: { draft.calories ?? 0 },
                            set: {
                                draft.calories = $0
                                if draft.candidate != nil { draft.labelEdited = true }
                            }
                        ), format: .number)
                            .keyboardType(.decimalPad)
                    }
                    editableRow("Calorie basis", value: draft.calorieBasis?.replacingOccurrences(of: "_", with: " ") ?? "Not recorded", field: .calorieBasis) {
                        TextField("Calorie basis (for example, per serving)", text: Binding(
                            get: { draft.calorieBasis ?? "" },
                            set: {
                                draft.calorieBasis = $0
                                if draft.candidate != nil { draft.labelEdited = true }
                            }
                        ))
                    }
                    editableRow("Serving size", value: draft.servingSize ?? "Not recorded", field: .servingSize) {
                        TextField("Printed serving size", text: Binding(
                            get: { draft.servingSize ?? "" },
                            set: {
                                draft.servingSize = $0
                                if draft.candidate != nil { draft.labelEdited = true }
                            }
                        ))
                    }
                    Text("Printed label claims")
                        .font(.headline)
                    Menu {
                        ForEach(LabelClaimCatalog.groups, id: \.title) { group in
                            Menu(group.title) {
                                ForEach(group.codes, id: \.self) { claim in
                                    Button {
                                        toggleClaim(claim)
                                    } label: {
                                        if (draft.dietaryClaims ?? []).contains(claim) {
                                            Label(displayLabel(claim), systemImage: "checkmark")
                                        } else {
                                            Text(displayLabel(claim))
                                        }
                                    }
                                }
                            }
                        }
                    } label: {
                        Label("Add printed claim", systemImage: "plus.circle")
                    }
                    if (draft.dietaryClaims ?? []).isEmpty && (draft.otherLabelClaims ?? []).isEmpty {
                        Text("No package claims recorded")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(draft.dietaryClaims ?? [], id: \.self) { claim in
                        HStack {
                            Text(displayLabel(claim))
                            Spacer()
                            Button { toggleClaim(claim) } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Remove \(displayLabel(claim)) claim")
                        }
                    }
                    ForEach(draft.otherLabelClaims ?? [], id: \.self) { claim in
                        HStack {
                            Text(claim)
                            Spacer()
                            Button { removeOtherClaim(claim) } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Remove \(claim) claim")
                        }
                    }
                    HStack {
                        TextField("Other claim, exactly as printed", text: $otherClaimInput)
                            .textInputAutocapitalization(.words)
                        Button("Add") { addOtherClaim() }
                            .disabled(otherClaimInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (draft.otherLabelClaims ?? []).count >= 8)
                    }
                    if !(draft.dietaryClaims ?? []).isEmpty || !(draft.otherLabelClaims ?? []).isEmpty {
                        Toggle("I checked these claims on the package", isOn: Binding(
                            get: { draft.dietaryClaimsConfirmed == true },
                            set: { draft.dietaryClaimsConfirmed = $0 }
                        ))
                    }
                    Text("Record only words printed on the whole package. These claims are not proof a food is safe for an allergy. Record explicit Contains or May contain statements separately; no statement visible means unknown.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(currentAllergens, id: \.code) { allergen in
                        editableRow(displayLabel(allergen.code), value: displayLabel(allergen.declaration), field: .allergen(allergen.code)) {
                            Picker("Declaration", selection: Binding(
                                get: { currentAllergens.first(where: { $0.code == allergen.code })?.declaration ?? "unknown" },
                                set: { updateAllergen(allergen.code, declaration: $0) }
                            )) {
                                Text("Contains").tag("contains")
                                Text("Cross-contact advisory").tag("cross_contact_advisory")
                                Text("Not declared on label").tag("not_declared_on_label")
                                Text("Unknown").tag("unknown")
                            }
                            .pickerStyle(.menu)
                            Button("Remove declaration", role: .destructive) {
                                draft.allergenOverrides = currentAllergens.filter { $0.code != allergen.code }
                                draft.labelEdited = true
                                editingField = nil
                            }
                        }
                    }
                    Menu {
                        ForEach(allergenCodes.filter { code in !currentAllergens.contains(where: { $0.code == code }) }, id: \.self) { code in
                            Button(displayLabel(code)) { updateAllergen(code, declaration: "contains") }
                        }
                    } label: {
                        Label("Add allergen declaration", systemImage: "plus.circle")
                    }
                    .disabled(currentAllergens.count == allergenCodes.count)
                    Text("Allergen corrections require admin review. Compare every declaration with the package; missing AI text does not mean allergen-free.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if draft.labelEdited == true {
                        Label("Corrected catalog nutrition — an admin will review this item.", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .disabled(isLocked)
            .navigationTitle("Verify donation")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isSubmitting || isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isLocked ? "Close" : "Cancel") { dismiss() }.disabled(isSubmitting || isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSubmitting ? "Submitting" : isLocked ? "Retry" : "Submit") {
                        Task { await submitDraft() }
                    }
                    .disabled(isSubmitting || isSaving || isReadingPhoto || isAddingPhotos || isAnalyzing)
                }
                ToolbarItem(placement: .bottomBar) {
                    if !isLocked {
                        Button(isSaving ? "Saving" : "Save on this iPhone", systemImage: "tray.and.arrow.down") {
                            Task { await saveDraft() }
                        }
                        .disabled(isSaving || isSubmitting || isReadingPhoto || isAddingPhotos || isAnalyzing)
                    }
                }
            }
            .sheet(isPresented: $showingPackageCamera) {
                PackagePhotoCamera { data in addPackagePhoto(data) }
                    .ignoresSafeArea()
            }
            .alert(submissionAlertTitle, isPresented: $showingSubmissionAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(submissionAlertMessage)
            }
            .fullScreenCover(item: $previewPhoto) { photo in
                PackagePhotoPreviewView(photos: previewPhotos, initialPhotoID: photo.id)
            }
            .onChange(of: selectedPackagePhotos) { _, photos in
                guard !photos.isEmpty else { return }
                Task {
                    isAddingPhotos = true
                    defer {
                        selectedPackagePhotos = []
                        isAddingPhotos = false
                    }
                    for photo in photos {
                        do {
                            guard let data = try await photo.loadTransferable(type: Data.self) else {
                                throw AppValidationError("Could not load a selected photo.")
                            }
                            addPackagePhoto(data)
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
            }
        }
    }

    private var sourceLabel: String {
        if let source = draft.candidate?.source { return source.replacingOccurrences(of: "_", with: " ").capitalized }
        return draft.scan == nil ? "Manual entry" : "Barcode without catalog match"
    }

    private var submissionActivityHint: String? {
        if isAnalyzing { return "Wait for photo analysis to finish before submitting." }
        if isReadingPhoto { return "Wait for date reading to finish before submitting." }
        if isAddingPhotos { return "Wait for photos to finish loading before submitting." }
        if isSubmitting { return "Submitting your donation…" }
        if isSaving { return "Saving your draft…" }
        return nil
    }

    private var currentAllergens: [AllergenDeclaration] {
        draft.allergenOverrides ?? draft.candidate?.allergens ?? []
    }

    private var allergenCodes: [String] {
        ["milk", "egg", "fish", "crustacean_shellfish", "tree_nuts", "peanuts", "wheat", "soybeans", "sesame"]
    }

    private func toggleClaim(_ claim: String) {
        var claims = draft.dietaryClaims ?? []
        if claims.contains(claim) { claims.removeAll { $0 == claim } }
        else { claims.append(claim) }
        draft.dietaryClaims = claims
        draft.dietaryClaimsConfirmed = false
        draft.labelEdited = true
    }

    private func addOtherClaim() {
        let claim = String(otherClaimInput.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        guard !claim.isEmpty else { return }
        var claims = draft.otherLabelClaims ?? []
        guard claims.count < 8 else { return }
        if !claims.contains(where: { $0.localizedCaseInsensitiveCompare(claim) == .orderedSame }) {
            claims.append(claim)
            draft.otherLabelClaims = claims
            draft.dietaryClaimsConfirmed = false
            draft.labelEdited = true
        }
        otherClaimInput = ""
    }

    private func removeOtherClaim(_ claim: String) {
        draft.otherLabelClaims = (draft.otherLabelClaims ?? []).filter { $0 != claim }
        draft.dietaryClaimsConfirmed = false
        draft.labelEdited = true
    }

    private func updateAllergen(_ code: String, declaration: String) {
        var values = currentAllergens
        if let index = values.firstIndex(where: { $0.code == code }) {
            values[index] = AllergenDeclaration(code: code, declaration: declaration, labelText: values[index].labelText)
        } else {
            values.append(AllergenDeclaration(code: code, declaration: declaration))
        }
        draft.allergenOverrides = values
        draft.labelEdited = true
    }

    @ViewBuilder
    private func editableRow<Editor: View>(_ title: String, value: String, field: IntakeEditField, highlight: Bool = false,
                                           @ViewBuilder editor: () -> Editor) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(value.isEmpty ? "Not entered" : value)
                        .padding(.horizontal, highlight ? 8 : 0)
                        .padding(.vertical, highlight ? 4 : 0)
                        .background(highlight ? Color.yellow.opacity(0.25) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button {
                    editingField = editingField == field ? nil : field
                } label: {
                    Image(systemName: "pencil")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Edit \(title)")
            }
            if editingField == field {
                editor()
                Button("Done") { editingField = nil }
                    .buttonStyle(.borderless)
            }
        }
        .disabled(isSubmitting || isSaving || isReadingPhoto || isAddingPhotos || isAnalyzing)
    }

    private var unitLabel: String {
        switch draft.quantityUnit {
        case "each": "Each"
        case "can": "Can"
        case "box": "Box"
        case "lb": "Pound"
        default: displayLabel(draft.quantityUnit)
        }
    }

    private var dateTypeLabel: String {
        switch draft.dateType {
        case "best_if_used_by": "Best if used by"
        case "best_before": "Best before"
        case "use_by": "Use by"
        case "expiration": "Expiration"
        case "sell_by": "Sell by"
        default: displayLabel(draft.dateType)
        }
    }

    private func displayLabel(_ value: String) -> String {
        if value == "non_gmo" { return "Non-GMO" }
        return value.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private var photoCount: Int {
        (draft.referencePhotos ?? []).count + (draft.packagePhotoData == nil ? 0 : 1)
    }

    private var previewPhotos: [IntakePhoto] {
        var photos = draft.referencePhotos ?? []
        if let data = draft.packagePhotoData {
            photos.append(IntakePhoto(id: draft.id, jpegData: data,
                                      capturedAt: draft.packagePhotoCapturedAt ?? .now))
        }
        return photos
    }

    private func analyzePackagePhotos() async {
        let photos = (draft.referencePhotos ?? []).compactMap(\.jpegData) + [draft.packagePhotoData].compactMap { $0 }
        guard photos.count == photoCount else {
            errorMessage = "A package photo is missing. Add it again before analysis."
            return
        }
        isAnalyzing = true
        errorMessage = nil
        defer { isAnalyzing = false }
        do {
            let result = try await analyze(photos)
            analysis = result
            if draft.dateSource == "AI suggestion · unverified" && !draft.dateConfirmed {
                draft.dateLabelRaw = ""
                draft.hasPrintedDate = false
                draft.dateValue = nil
                draft.dateSource = "Not captured"
                draft.dateConfidence = nil
            }
            let allowedDateTypes: Set<String> = ["best_if_used_by", "best_before", "use_by", "expiration", "sell_by"]
            let modelDateType = result.printedDateType.flatMap { allowedDateTypes.contains($0) ? $0 : nil }
            if draft.dateLabelRaw.isEmpty,
               let printedDate = result.printedDate?.trimmingCharacters(in: .whitespacesAndNewlines),
               !printedDate.isEmpty,
               !["not visible", "not found", "unknown", "none", "n/a"].contains(printedDate.lowercased()) {
                draft.dateLabelRaw = printedDate
                draft.hasPrintedDate = true
                draft.dateConfirmed = false
                draft.dateConfidence = nil
                draft.dateSource = "AI suggestion · unverified"
                let match = DateLabelParser.bestMatch(in: [(text: printedDate, confidence: 1)])
                if let match {
                    draft.dateValue = match.date
                }
                if let match, match.dateType != "unknown" {
                    if let modelDateType, modelDateType != match.dateType {
                        draft.dateType = "unknown"
                        errorMessage = "AI and captured label text disagree about the date type. Check the package and choose the correct type."
                    } else {
                        draft.dateType = match.dateType
                    }
                } else {
                    draft.dateType = modelDateType ?? "unknown"
                }
            } else if draft.hasPrintedDate, !draft.dateConfirmed, draft.dateType == "unknown", let modelDateType {
                // OCR may have read the digits but missed the nearby date-type label.
                draft.dateType = modelDateType
                draft.dateConfidence = nil
            }
            if draft.productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let name = result.productName {
                draft.productName = name
                draft.usedPhotoSuggestions = true
            }
            if draft.brand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let brand = result.brand {
                draft.brand = brand
                draft.usedPhotoSuggestions = true
            }
            if draft.calories == nil, let calories = result.calories, let basis = result.calorieBasis {
                draft.calories = calories
                draft.calorieBasis = basis
                draft.servingSize = result.servingSize
                draft.usedPhotoSuggestions = true
            }
            if !result.dietaryClaims.isEmpty && draft.dietaryClaimsConfirmed != true {
                draft.dietaryClaims = result.dietaryClaims
                draft.dietaryClaimsConfirmed = false
                draft.labelEdited = true
            }
            if !result.otherLabelClaims.isEmpty && draft.dietaryClaimsConfirmed != true {
                draft.otherLabelClaims = result.otherLabelClaims
                draft.dietaryClaimsConfirmed = false
                draft.labelEdited = true
            }
            if analysis?.productName == nil && errorMessage == nil {
                errorMessage = "The model could not identify the product. Add a clear front-label photo or enter its name yourself."
            }
        } catch {
            errorMessage = "Photo analysis failed: \(error.localizedDescription). You can retry or enter details manually."
        }
    }

    private func applyPhotoSuggestions(_ result: PhotoAnalysisResponse) {
        if let name = result.productName { draft.productName = name }
        if let brand = result.brand { draft.brand = brand }
        draft.usedPhotoSuggestions = true
        errorMessage = nil
    }

    private func invalidateAnalysis() {
        if let analysis, draft.usedPhotoSuggestions == true {
            if draft.productName == analysis.productName { draft.productName = "" }
            if draft.brand == analysis.brand { draft.brand = "" }
            draft.usedPhotoSuggestions = nil
        }
        analysis = nil
        if draft.dateSource == "AI suggestion · unverified" && !draft.dateConfirmed {
            draft.hasPrintedDate = false
            draft.dateValue = nil
            draft.dateLabelRaw = ""
            draft.dateSource = "Not captured"
            draft.dateConfidence = nil
        }
    }

    private func addPackagePhoto(_ data: Data) {
        guard photoCount < 8 else {
            errorMessage = "The eight-photo limit has been reached. Remove a photo to add another."
            return
        }
        do {
            let jpeg = try PackageDateOCR.normalizedJPEG(from: data)
            var photos = draft.referencePhotos ?? []
            photos.append(IntakePhoto(id: UUID(), jpegData: jpeg, capturedAt: .now))
            draft.referencePhotos = photos
            invalidateAnalysis()
            errorMessage = nil
        } catch {
            errorMessage = "Could not add photo: \(error.localizedDescription)"
        }
    }

    private func removeDatePhoto() {
        invalidateAnalysis()
        draft.packagePhotoData = nil
        draft.packagePhotoCapturedAt = nil
        clearPhotoDateFields()
    }

    private func clearPhotoDateFields() {
        if draft.dateSource == "Package photo" || draft.dateSource == "Photo, corrected" {
            draft.hasPrintedDate = false
            draft.dateValue = nil
            draft.dateLabelRaw = ""
            draft.dateSource = "Not captured"
            draft.dateConfidence = nil
            draft.dateConfirmed = false
        }
    }

    private func selectDatePhoto(_ photo: IntakePhoto) async {
        guard let jpeg = photo.jpegData,
              var photos = draft.referencePhotos,
              let index = photos.firstIndex(where: { $0.id == photo.id }) else {
            errorMessage = "This package photo is unavailable. Add it again before reading the date."
            return
        }
        isReadingPhoto = true
        errorMessage = nil
        defer { isReadingPhoto = false }
        photos.remove(at: index)
        if let oldDatePhoto = draft.packagePhotoData {
            photos.append(IntakePhoto(id: UUID(), jpegData: oldDatePhoto,
                                      capturedAt: draft.packagePhotoCapturedAt ?? .now))
        }
        draft.referencePhotos = photos
        draft.packagePhotoData = jpeg
        draft.packagePhotoCapturedAt = photo.capturedAt
        do {
            try await recognizeDate(jpeg)
        } catch {
            errorMessage = "Could not read the selected photo: \(error.localizedDescription)"
        }
    }

    private func submitDraft() async {
        if !draft.submissionIssues.isEmpty {
            submissionAlertTitle = "Before submitting"
            submissionAlertMessage = draft.submissionIssues.joined(separator: "\n\n")
            showingSubmissionAlert = true
            return
        }
        isSubmitting = true
        errorMessage = nil
        do {
            try await submit(draft)
            dismiss()
        } catch {
            isLocked = isLockedAfterFailure(draft.id)
            errorMessage = isLocked ? "Submission did not complete. This item is saved on this iPhone; retry when connected. \(error.localizedDescription)" : error.localizedDescription
            isSubmitting = false
            submissionAlertTitle = "Could not submit donation"
            submissionAlertMessage = errorMessage ?? "Please try again."
            showingSubmissionAlert = true
        }
    }

    private func saveDraft() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await save(draft)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func recognizeDate(_ jpeg: Data) async throws {
        draft.hasPrintedDate = false
        draft.dateValue = nil
        draft.dateLabelRaw = ""
        draft.dateSource = "Not captured"
        draft.dateConfidence = nil
        draft.dateConfirmed = false
        guard let match = try await PackageDateOCR.recognize(jpegData: jpeg) else {
            errorMessage = "No complete date was recognized. Select another photo or enter the date manually."
            return
        }
        draft.hasPrintedDate = true
        draft.dateValue = match.date
        draft.dateType = match.dateType
        draft.dateLabelRaw = match.rawText
        draft.dateSource = "Package photo"
        draft.dateConfidence = match.confidence
    }
}

private struct PackagePhotoPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let photos: [IntakePhoto]
    @State private var selectedPhotoID: UUID

    init(photos: [IntakePhoto], initialPhotoID: UUID) {
        self.photos = photos
        _selectedPhotoID = State(initialValue: initialPhotoID)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TabView(selection: $selectedPhotoID) {
                ForEach(photos) { photo in
                    ZStack {
                        Color.black
                        if let data = photo.jpegData, let image = UIImage(data: data) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { dismiss() }
                    .tag(photo.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
        }
        .overlay(alignment: .top) {
            HStack {
                Text("\((photos.firstIndex { $0.id == selectedPhotoID } ?? 0) + 1) of \(photos.count)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.18), in: Circle())
                }
                .accessibilityLabel("Close photo preview")
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
        .overlay(alignment: .bottom) {
            Text(photos.count > 1 ? "Swipe for another photo · Tap to close" : "Tap to close")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
                .padding(.bottom, 16)
        }
        .statusBarHidden()
    }
}
