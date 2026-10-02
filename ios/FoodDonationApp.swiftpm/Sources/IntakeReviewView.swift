import FoodDonationCore
import PhotosUI
import SwiftUI
import UIKit

struct IntakeReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: IntakeDraft
    @State private var isSubmitting = false
    @State private var isSaving = false
    @State private var isLocked: Bool
    @State private var isReadingPhoto = false
    @State private var isAddingPhotos = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedPackagePhotos: [PhotosPickerItem] = []
    @State private var showingCamera = false
    @State private var showingPackageCamera = false
    @State private var previewPhoto: IntakePhoto?
    @State private var errorMessage: String?
    let submit: (IntakeDraft) async throws -> Void
    let save: (IntakeDraft) async throws -> Void
    let isLockedAfterFailure: (UUID) -> Bool

    init(draft: IntakeDraft, initiallyLocked: Bool, submit: @escaping (IntakeDraft) async throws -> Void,
         save: @escaping (IntakeDraft) async throws -> Void, isLockedAfterFailure: @escaping (UUID) -> Bool) {
        _draft = State(initialValue: draft)
        _isLocked = State(initialValue: initiallyLocked)
        self.submit = submit
        self.save = save
        self.isLockedAfterFailure = isLockedAfterFailure
    }

    var body: some View {
        NavigationStack {
            Form {
                if isLocked {
                    Section {
                        Label("Saved on this iPhone. Details are locked while submission is pending; retry when the server is available.", systemImage: "tray.full")
                            .foregroundStyle(.orange)
                    }
                }
                Section("Product") {
                    TextField("Product name", text: $draft.productName)
                    TextField("Brand", text: $draft.brand)
                    Picker("Category", selection: Binding(
                        get: { FoodCategory.from(raw: draft.category ?? draft.candidate?.category).rawValue },
                        set: { draft.category = $0 }
                    )) {
                        ForEach(FoodCategory.allCases) { category in
                            Text(category.title).tag(category.rawValue)
                        }
                    }
                    if let code = draft.scan?.raw, !code.isEmpty {
                        LabeledContent("Scanned code", value: code)
                            .font(.system(.body, design: .monospaced))
                    }
                    LabeledContent("Source", value: sourceLabel)
                    if let candidate = draft.candidate {
                        LabeledContent("Confidence", value: candidate.confidence.formatted(.percent.precision(.fractionLength(0))))
                    } else {
                        Label("No catalog match. Add package photos and confirm what you can; an admin will review this item before it enters inventory.", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                if draft.candidate == nil {
                    Section("Package photos (\(photoCount)/8)") {
                        Text("Take photos of the front, ingredients, nutrition facts, barcode, and other useful sides. Enter the product name yourself before submitting; photos help an admin review it but are not yet read automatically. The date-label photo counts toward the eight-photo limit.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !(draft.referencePhotos ?? []).isEmpty {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                                ForEach(draft.referencePhotos ?? []) { photo in
                                    if let data = photo.jpegData, let image = UIImage(data: data) {
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
                                            .buttonStyle(.plain)
                                            .accessibilityLabel("Preview package photo")
                                            Button {
                                                draft.referencePhotos?.removeAll { $0.id == photo.id }
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.title2)
                                                    .foregroundStyle(.white)
                                                    .shadow(color: .black.opacity(0.8), radius: 2)
                                                    .frame(width: 44, height: 44)
                                            }
                                            .buttonStyle(.plain)
                                            .accessibilityLabel("Remove package photo")
                                            .disabled(isAddingPhotos || isSubmitting)
                                        }
                                    }
                                }
                            }
                        }
                        HStack(spacing: 0) {
                            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                                Button { showingPackageCamera = true } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: "camera")
                                        Text("Take photo")
                                    }
                                    .font(.subheadline.weight(.semibold))
                                    .frame(minHeight: 44)
                                }
                                Spacer(minLength: 24)
                            }
                            PhotosPicker(selection: $selectedPackagePhotos, maxSelectionCount: max(1, 8 - photoCount), matching: .images) {
                                HStack(spacing: 5) {
                                    Image(systemName: "photo.on.rectangle")
                                    Text("Choose photos")
                                }
                                .font(.subheadline.weight(.semibold))
                                .frame(minHeight: 44)
                            }
                        }
                        .disabled(photoCount >= 8 || isAddingPhotos || isReadingPhoto || isSubmitting)
                        if isAddingPhotos { ProgressView("Adding photos…") }
                    }
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
                        ZStack(alignment: .topTrailing) {
                            Button {
                                previewPhoto = IntakePhoto(id: draft.id, jpegData: data,
                                                          capturedAt: draft.packagePhotoCapturedAt ?? .now)
                            } label: {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxHeight: 180)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Preview date-label photo")
                            Button {
                                removeDatePhoto()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.8), radius: 2)
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove date-label photo")
                            .disabled(isReadingPhoto || isSubmitting)
                        }
                    }
                    HStack {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button("Take photo", systemImage: "camera") { showingCamera = true }
                        }
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            Label("Choose photo", systemImage: "photo")
                        }
                    }
                    .disabled(isReadingPhoto || isAddingPhotos || isSubmitting || (draft.packagePhotoData == nil && photoCount >= 8))

                    if isReadingPhoto {
                        ProgressView("Reading printed date…")
                    }
                    Text("Aim at the printed date. Check the on-device OCR result against the package. The photo is saved with this intake when you submit.")
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

                if draft.calories != nil || !(draft.candidate?.allergens.isEmpty ?? true) {
                    Section("Label information") {
                        if let calories = draft.calories {
                            LabeledContent("Calories", value: calories.formatted())
                            LabeledContent("Basis", value: (draft.calorieBasis ?? "unknown").replacingOccurrences(of: "_", with: " "))
                        }
                        ForEach(draft.candidate?.allergens ?? [], id: \.code) { allergen in
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
                    .disabled(isSubmitting || isSaving || isReadingPhoto || isAddingPhotos || (draft.hasPrintedDate && !draft.dateConfirmed))
                }
                ToolbarItem(placement: .bottomBar) {
                    if !isLocked {
                        Button(isSaving ? "Saving" : "Save on this iPhone", systemImage: "tray.and.arrow.down") {
                            Task { await saveDraft() }
                        }
                        .disabled(isSaving || isSubmitting || isReadingPhoto || isAddingPhotos)
                    }
                }
            }
            .sheet(isPresented: $showingCamera) {
                PackagePhotoCamera { data in
                    Task { await readPhoto(data) }
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showingPackageCamera) {
                PackagePhotoCamera { data in addPackagePhoto(data) }
                    .ignoresSafeArea()
            }
            .fullScreenCover(item: $previewPhoto) { photo in
                PackagePhotoPreviewView(photos: previewPhotos, initialPhotoID: photo.id)
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
            errorMessage = nil
        } catch {
            errorMessage = "Could not add photo: \(error.localizedDescription)"
        }
    }

    private func removeDatePhoto() {
        draft.packagePhotoData = nil
        draft.packagePhotoCapturedAt = nil
        if draft.dateSource == "Package photo" || draft.dateSource == "Photo, corrected" {
            draft.hasPrintedDate = false
            draft.dateValue = nil
            draft.dateLabelRaw = ""
            draft.dateSource = "Not captured"
            draft.dateConfidence = nil
            draft.dateConfirmed = false
        }
    }

    private func submitDraft() async {
        isSubmitting = true
        errorMessage = nil
        do {
            try await submit(draft)
            dismiss()
        } catch {
            isLocked = isLockedAfterFailure(draft.id)
            errorMessage = isLocked ? "Submission did not complete. This item is saved on this iPhone; retry when connected. \(error.localizedDescription)" : error.localizedDescription
            isSubmitting = false
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

    private func readPhoto(_ data: Data) async {
        guard draft.packagePhotoData != nil || photoCount < 8 else {
            errorMessage = "The eight-photo limit has been reached. Remove a photo to add the date label."
            return
        }
        isReadingPhoto = true
        errorMessage = nil
        defer { isReadingPhoto = false }
        do {
            let jpeg = try PackageDateOCR.normalizedJPEG(from: data)
            draft.packagePhotoData = jpeg
            draft.packagePhotoCapturedAt = .now
            guard let match = try await PackageDateOCR.recognize(jpegData: jpeg) else {
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
