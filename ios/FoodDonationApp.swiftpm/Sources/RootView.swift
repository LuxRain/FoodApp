import FoodDonationCore
import SwiftUI

struct RootView: View {
    @State private var model = AppModel()
    @State private var showingScanner = false
    @State private var reviewDraft: IntakeDraft?
    @State private var alertMessage: String?

    var body: some View {
        TabView {
            NavigationStack {
                DashboardView(model: model, scan: { showingScanner = true })
                    .navigationTitle("Donations")
            }
            .tabItem { Label("Dashboard", systemImage: "shippingbox") }

            NavigationStack {
                ScanStartView(isLookingUp: model.isLookingUp) {
                    showingScanner = true
                }
                .navigationTitle("New intake")
            }
            .tabItem { Label("Scan", systemImage: "barcode.viewfinder") }

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
                Task {
                    do {
                        reviewDraft = try await model.prepareDraft(rawValue: rawValue)
                    } catch {
                        alertMessage = error.localizedDescription
                    }
                }
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

    var body: some View {
        ContentUnavailableView {
            Label(isLookingUp ? "Looking up product" : "Ready to scan", systemImage: isLookingUp ? "magnifyingglass" : "barcode.viewfinder")
        } description: {
            Text("Scan one packaged product. You will verify quantity, date, storage, and package condition before submission.")
        } actions: {
            Button("Open scanner", action: scan)
                .buttonStyle(.borderedProminent)
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
                TextField("User ID", text: $model.userID)
                    .textInputAutocapitalization(.never)
                TextField("Organization ID", text: $model.organizationID)
                    .textInputAutocapitalization(.never)
                    .font(.system(.caption, design: .monospaced))
                TextField("Location ID", text: $model.locationID)
                    .textInputAutocapitalization(.never)
                    .font(.system(.caption, design: .monospaced))
            }
            Section {
                Button("Restore development defaults", action: model.resetDevelopmentSettings)
            }
        }
    }
}
