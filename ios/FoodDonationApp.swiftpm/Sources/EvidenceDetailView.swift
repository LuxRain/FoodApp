import FoodDonationCore
import SwiftUI
import UIKit

struct EvidenceDetailView: View {
    let item: DonationDashboardItem
    let model: AppModel
    @State private var evidence: [EvidenceAsset] = []
    @State private var images: [UUID: UIImage] = [:]
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.product.name).font(.title2.bold())
                    if let brand = item.product.brand { Text(brand).foregroundStyle(.secondary) }
                    LabeledContent("Quantity", value: "\(item.onHand.quantity.formatted()) \(item.onHand.unit)")
                    LabeledContent("Printed date", value: item.date.value ?? "Not recorded")
                    LabeledContent("Date type", value: item.date.type.replacingOccurrences(of: "_", with: " ").capitalized)
                    LabeledContent("Status", value: item.intakeStatus.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                }

                Text("Package evidence").font(.title3.bold())
                if isLoading {
                    ProgressView("Loading photos")
                } else if let errorMessage {
                    ContentUnavailableView("Could not load evidence", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
                    Button("Try again") { Task { await loadEvidence() } }
                } else if evidence.isEmpty {
                    ContentUnavailableView("No photo evidence", systemImage: "photo", description: Text("This intake item has no stored package photo."))
                } else {
                    ForEach(evidence) { asset in
                        VStack(alignment: .leading, spacing: 8) {
                            if let image = images[asset.id] {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: .infinity)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .accessibilityLabel("Date label photo")
                            }
                            Text("Date label · \(asset.capturedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle("Donation details")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadEvidence() }
    }

    private func loadEvidence() async {
        isLoading = true
        errorMessage = nil
        do {
            let assets = try await model.evidence(for: item.intakeItemId)
            var loaded: [UUID: UIImage] = [:]
            for asset in assets {
                let data = try await model.evidenceImage(for: item.intakeItemId, evidenceID: asset.id)
                if let image = UIImage(data: data) { loaded[asset.id] = image }
            }
            evidence = assets
            images = loaded
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
