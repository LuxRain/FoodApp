import FoodDonationCore
import SwiftUI

struct DashboardView: View {
    let model: AppModel
    let scan: () -> Void

    var body: some View {
        Group {
            switch model.dashboardState {
            case .idle, .loading where model.dashboardItems.isEmpty:
                ProgressView("Loading donations")
            case let .failed(message) where model.dashboardItems.isEmpty:
                ContentUnavailableView {
                    Label("Cannot load donations", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") { Task { await model.loadDashboard() } }
                        .buttonStyle(.borderedProminent)
                }
            default:
                dashboard
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: scan) {
                Label("Scan donation", systemImage: "barcode.viewfinder")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
            }
            .buttonStyle(.borderedProminent)
            .padding()
            .background(.regularMaterial)
        }
    }

    private var dashboard: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                summary

                if model.dashboardItems.isEmpty {
                    ContentUnavailableView(
                        "No donations yet",
                        systemImage: "shippingbox",
                        description: Text("Scan the first packaged item to create inventory.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Next to distribute")
                            .font(.title2.bold())
                        ForEach(model.dashboardItems) { item in
                            DonationRow(item: item)
                        }
                    }
                }
            }
            .padding()
        }
        .refreshable { await model.loadDashboard() }
    }

    private var summary: some View {
        HStack(spacing: 12) {
            metric(value: String(receivedToday), label: "Received today")
            metric(value: String(needsReview), label: "Need review")
        }
    }

    private var receivedToday: Int {
        model.dashboardItems.filter { Calendar.current.isDateInToday($0.receivedAt) }.count
    }

    private var needsReview: Int {
        model.dashboardItems.filter { [.pendingAdminReview, .quarantined].contains($0.intakeStatus) }.count
    }

    private func metric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value).font(.largeTitle.bold())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct DonationRow: View {
    let item: DonationDashboardItem

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(urgencyColor).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.product.name).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
                Text(statusLabel).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(item.onHand.quantity.formatted())
                .font(.headline.monospacedDigit())
            Text(item.onHand.unit)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        guard let value = item.date.value else { return "No printed date" }
        let type = item.date.type.replacingOccurrences(of: "_", with: " ").capitalized
        return "\(type) \(value)"
    }

    private var statusLabel: String {
        item.intakeStatus.rawValue.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private var urgencyColor: Color {
        switch item.date.urgency {
        case .expiredOrPast: .red
        case .dueSoon: .orange
        case .good: .green
        case .noDate: .gray
        }
    }
}
