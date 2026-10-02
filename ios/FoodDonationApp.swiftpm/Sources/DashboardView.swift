import FoodDonationCore
import SwiftUI

struct DashboardView: View {
    let model: AppModel
    let scan: () -> Void

    var body: some View {
        Group {
            switch model.dashboardState {
            case .idle where model.dashboardItems.isEmpty,
                 .loading where model.dashboardItems.isEmpty:
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
                if case let .failed(message) = model.dashboardState {
                    Label("Could not refresh: \(message)", systemImage: "wifi.exclamationmark")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
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
                        VStack(alignment: .leading, spacing: 3) {
                            Menu {
                                ForEach(DashboardSort.allCases, id: \.self) { sort in
                                    Button {
                                        model.dashboardSort = sort
                                        Task { await model.loadDashboard() }
                                    } label: {
                                        if model.dashboardSort == sort {
                                            Label(sort.title, systemImage: "checkmark")
                                        } else {
                                            Text(sort.title)
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Text("Donation records")
                                        .font(.title2.bold())
                                        .foregroundStyle(.primary)
                                    Image(systemName: "chevron.down")
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(.green)
                                }
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                            }
                            .accessibilityLabel("Sort donation records. Current order: \(model.dashboardSort.title)")
                            Text("Sorted by \(model.dashboardSort.title.lowercased())")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(model.dashboardItems) { item in
                            NavigationLink {
                                EvidenceDetailView(item: item, model: model)
                            } label: {
                                DonationRow(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding()
        }
        .refreshable { await model.loadDashboard() }
        .scrollBounceBehavior(.always, axes: .vertical)
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
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: category.symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 24) {
                    Text(displayName)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel(item.product.name)
                    Text("\(item.onHand.quantity.formatted()) \(item.onHand.unit)")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(width: 100, alignment: .leading)
                }
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let warning {
                    HStack(spacing: 6) {
                        Image(systemName: warning.icon)
                            .foregroundStyle(warning.color)
                        Text(warning.text)
                            .foregroundStyle(.primary)
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(warning.color.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
                }
                Text("\(category.title) · \(statusLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        guard let value = item.date.value else { return "No printed date" }
        let type = item.date.type.replacingOccurrences(of: "_", with: " ").capitalized
        return "\(type) \(value)"
    }

    private var displayName: String {
        let name = item.product.name
        return name.count > 40 ? String(name.prefix(40)).trimmingCharacters(in: .whitespaces) + "…" : name
    }

    private var statusLabel: String {
        item.intakeStatus.rawValue.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private var category: FoodCategory {
        FoodCategory.from(raw: item.product.category)
    }

    private var warning: (text: String, icon: String, color: Color)? {
        guard let days = item.date.daysRemaining else { return nil }
        if days < 0 { return ("Past printed date — review before distribution", "exclamationmark.triangle.fill", .red) }
        if days == 0 { return ("Printed date is today", "exclamationmark.triangle.fill", .red) }
        if days <= 7 { return ("Printed date in \(days) days", "exclamationmark.triangle.fill", .red) }
        if days <= 14 { return ("Printed date in \(days) days", "clock.fill", .yellow) }
        return nil
    }
}
