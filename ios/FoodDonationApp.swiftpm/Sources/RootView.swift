import FoodDonationCore
import SwiftUI

private enum AppTab: Hashable {
    case dashboard, scan, saved, review, settings
}

struct RootView: View {
    @State private var model = AppModel()
    @State private var selectedTab: AppTab = .dashboard
    @State private var showingScanner = false
    @State private var openPhotoFallbackAfterScanner = false
    @State private var reviewDraft: IntakeDraft?
    @State private var alertMessage: String?
    @State private var showingLookupFailure = false
    @State private var failedScanRawValue = ""
    @State private var lookupFailureMessage = ""

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                DashboardView(model: model, scan: { showingScanner = true }, openReview: { selectedTab = .review })
                    .navigationTitle("Donations")
            }
            .tabItem { Label("Dashboard", systemImage: "shippingbox") }
            .tag(AppTab.dashboard)

            NavigationStack {
                ScanStartView(isLookingUp: model.isLookingUp,
                              scan: { showingScanner = true },
                              manualEntry: { reviewDraft = model.manualDraft() })
                .navigationTitle("New intake")
            }
            .tabItem { Label("Scan", systemImage: "barcode.viewfinder") }
            .tag(AppTab.scan)

            NavigationStack {
                SavedDraftsView(model: model) { draft in
                    reviewDraft = draft
                }
                .navigationTitle("Saved drafts")
            }
            .tabItem { Label("Saved", systemImage: "tray.full") }
            .tag(AppTab.saved)

            if model.userRole == .admin {
                NavigationStack {
                    AdminReviewView(model: model)
                        .navigationTitle("Review queue")
                }
                .tabItem { Label("Review", systemImage: "checklist") }
                .tag(AppTab.review)
            }

            NavigationStack {
                SettingsView(model: model)
                    .navigationTitle("Settings")
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
            .tag(AppTab.settings)
        }
        .tint(.green)
        .onChange(of: model.userRole) { _, role in
            if role != .admin && selectedTab == .review { selectedTab = .dashboard }
        }
        .task {
            await model.loadSavedDrafts()
            await model.loadDashboard()
        }
        .sheet(isPresented: $showingScanner, onDismiss: {
            if openPhotoFallbackAfterScanner {
                openPhotoFallbackAfterScanner = false
                reviewDraft = model.manualDraft()
            }
        }) {
            ScannerSheet(onScan: { rawValue in
                showingScanner = false
                Task { await lookUp(rawValue) }
            }, onNoBarcode: {
                openPhotoFallbackAfterScanner = true
                showingScanner = false
            })
        }
        .sheet(item: $reviewDraft) { draft in
            IntakeReviewView(
                draft: draft,
                initiallyLocked: model.isDraftLocked(draft.id),
                submit: { updatedDraft in
                    let result = try await model.submit(updatedDraft)
                    alertMessage = receiptMessage(for: result)
                },
                save: { updatedDraft in try await model.saveDraft(updatedDraft) },
                isLockedAfterFailure: { model.isDraftLocked($0) }
            )
        }
        .alert("Food Donation", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
        .confirmationDialog("Could not look up product", isPresented: $showingLookupFailure, titleVisibility: .visible) {
            Button("Retry lookup") {
                Task { await lookUp(failedScanRawValue) }
            }
            Button("Add photos or enter manually") {
                reviewDraft = model.manualDraft(rawValue: failedScanRawValue)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(lookupFailureMessage)
        }
    }

    private func lookUp(_ rawValue: String) async {
        do {
            reviewDraft = try await model.prepareDraft(rawValue: rawValue)
        } catch {
            lookupFailureMessage = "\(error.localizedDescription) You can retry or enter the product details yourself."
            failedScanRawValue = rawValue
            showingLookupFailure = true
        }
    }

    private func receiptMessage(for response: SubmitItemResponse) -> String {
        switch response.status {
        case .autoAccepted, .adminAccepted:
            "Received into inventory."
        case .pendingAdminReview:
            "Submitted for admin review: \(response.routingReasonCodes.joined(separator: ", "))."
        case .quarantined:
            "The item was quarantined."
        case .rejected:
            "The item was rejected."
        default:
            "Submission status: \(response.status.rawValue.replacingOccurrences(of: "_", with: " "))."
        }
    }
}

private struct ScanStartView: View {
    let isLookingUp: Bool
    let scan: () -> Void
    let manualEntry: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 28) {
                    Spacer(minLength: 24)

                    VStack(spacing: 16) {
                        Image(systemName: isLookingUp ? "magnifyingglass" : "barcode.viewfinder")
                            .font(.system(size: 48, weight: .medium))
                            .foregroundStyle(.green)
                            .accessibilityHidden(true)
                        Text(isLookingUp ? "Looking up product" : "Ready to scan")
                            .font(.title.bold())
                        Text("Scan one packaged product. You will verify quantity, date, storage, and package condition before submission.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    VStack(spacing: 16) {
                        Button(action: scan) {
                            actionLabel("Open scanner", detail: "Use the iPhone camera", icon: "camera.viewfinder")
                                .foregroundStyle(.white)
                                .background(.green, in: RoundedRectangle(cornerRadius: 20))
                        }
                        .accessibilityHint("Scan a package barcode")

                        Button(action: manualEntry) {
                            actionLabel("Enter item manually", detail: "No barcode or scanner available", icon: "square.and.pencil")
                                .foregroundStyle(.primary)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 20)
                                        .strokeBorder(.green.opacity(0.5), lineWidth: 1)
                                }
                        }
                        .accessibilityHint("Enter product details without scanning")
                    }
                    .buttonStyle(.plain)
                    .disabled(isLookingUp)

                    if isLookingUp {
                        ProgressView()
                            .accessibilityLabel("Looking up product")
                    }

                    Spacer(minLength: 24)
                }
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height)
                .padding(.horizontal, 24)
            }
        }
    }

    private func actionLabel(_ title: String, detail: String, icon: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline)
                    .opacity(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, minHeight: 76)
        .contentShape(RoundedRectangle(cornerRadius: 20))
    }
}

private struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("Sign-in design") {
                NavigationLink("Preview sign-in screen") {
                    SignInPreviewView()
                        .navigationBarTitleDisplayMode(.inline)
                }
                Text("Preview only. No sign-in code is sent and your current development identity stays active.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Development server") {
                TextField("API URL", text: $model.apiURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Text("Use 127.0.0.1 in the Simulator. On an iPhone, use the Mac's Wi-Fi IP address.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Development identity") {
                Picker("Role", selection: $model.userRole) {
                    Text("Volunteer").tag(UserRole.regularUser)
                    Text("Admin").tag(UserRole.admin)
                }
                .onChange(of: model.userRole) { _, role in
                    if role == .admin && model.userID == "regular-demo" { model.userID = "admin-demo" }
                    if role == .regularUser && model.userID == "admin-demo" { model.userID = "regular-demo" }
                }
                TextField("User ID", text: $model.userID)
                    .textInputAutocapitalization(.never)
                TextField("Organization ID", text: $model.organizationID)
                    .textInputAutocapitalization(.never)
                    .font(.system(.caption, design: .monospaced))
                TextField("Location ID", text: $model.locationID)
                    .textInputAutocapitalization(.never)
                    .font(.system(.caption, design: .monospaced))
                Text("These identity settings are for local development only; they are not production sign-in.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("Restore development defaults", action: model.resetDevelopmentSettings)
            }
        }
    }
}
