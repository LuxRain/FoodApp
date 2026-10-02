import FoodDonationCore
import SwiftUI

struct RootView: View {
    @State private var model = AppModel()
    @State private var showingScanner = false
    @State private var reviewDraft: IntakeDraft?
    @State private var alertMessage: String?
    @State private var showingLookupFailure = false
    @State private var failedScanRawValue = ""
    @State private var lookupFailureMessage = ""

    var body: some View {
        TabView {
            NavigationStack {
                DashboardView(model: model, scan: { showingScanner = true })
                    .navigationTitle("Donations")
            }
            .tabItem { Label("Dashboard", systemImage: "shippingbox") }

            NavigationStack {
                ScanStartView(isLookingUp: model.isLookingUp,
                              scan: { showingScanner = true },
                              manualEntry: { reviewDraft = model.manualDraft() })
                .navigationTitle("New intake")
            }
            .tabItem { Label("Scan", systemImage: "barcode.viewfinder") }

            if model.userRole == .admin {
                NavigationStack {
                    AdminReviewView(model: model)
                        .navigationTitle("Review queue")
                }
                .tabItem { Label("Review", systemImage: "checklist") }
            }

            NavigationStack {
                SettingsView(model: model)
                    .navigationTitle("Settings")
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(.green)
        .task { await model.loadDashboard() }
        .sheet(isPresented: $showingScanner) {
            ScannerSheet { rawValue in
                showingScanner = false
                Task { await lookUp(rawValue) }
            }
        }
        .sheet(item: $reviewDraft) { draft in
            IntakeReviewView(draft: draft) { updatedDraft in
                let result = try await model.submit(updatedDraft)
                alertMessage = receiptMessage(for: result)
            }
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
            Button("Enter manually") {
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
        ContentUnavailableView {
            Label(isLookingUp ? "Looking up product" : "Ready to scan", systemImage: isLookingUp ? "magnifyingglass" : "barcode.viewfinder")
        } description: {
            Text("Scan one packaged product. You will verify quantity, date, storage, and package condition before submission.")
        } actions: {
            VStack {
                Button("Open scanner", action: scan)
                    .buttonStyle(.borderedProminent)
                Button("Enter item manually", action: manualEntry)
                    .buttonStyle(.bordered)
            }
            .disabled(isLookingUp)
        }
    }
}

private struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
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
