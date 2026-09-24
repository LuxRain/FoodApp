import FoodDonationCore
import SwiftUI

struct RootView: View {
    @State private var showingScanner = false
    @State private var scannedCode: ParsedScan?

    var body: some View {
        TabView {
            NavigationStack {
                DashboardView(scannedCode: scannedCode) {
                    showingScanner = true
                }
                .navigationTitle("Donations")
            }
            .tabItem { Label("Dashboard", systemImage: "shippingbox") }

            NavigationStack {
                IntakeStatusView(scannedCode: scannedCode) {
                    showingScanner = true
                }
                .navigationTitle("New intake")
            }
            .tabItem { Label("Scan", systemImage: "barcode.viewfinder") }
        }
        .tint(.green)
        .sheet(isPresented: $showingScanner) {
            ScannerSheet { rawValue in
                scannedCode = ScanParser.parse(rawValue)
                showingScanner = false
            }
        }
    }
}

private struct DashboardView: View {
    let scannedCode: ParsedScan?
    let scan: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                summary

                VStack(alignment: .leading, spacing: 12) {
                    Text("Next to distribute")
                        .font(.title2.bold())
                    urgencyRow(title: "Black beans", detail: "Best before Sep 29", color: .orange)
                    urgencyRow(title: "Whole grain pasta", detail: "Best before Oct 12", color: .green)
                    urgencyRow(title: "Shelf-stable milk", detail: "No printed date", color: .gray)
                }

                if let scannedCode {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Latest scan", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .foregroundStyle(.green)
                        Text(scannedCode.normalizedGTIN ?? scannedCode.raw)
                            .font(.system(.body, design: .monospaced))
                        Text(scannedCode.scheme.rawValue.replacingOccurrences(of: "_", with: " ").uppercased())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .padding()
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

    private var summary: some View {
        HStack(spacing: 12) {
            metric(value: "24", label: "Received today")
            metric(value: "3", label: "Need review")
        }
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

    private func urgencyRow(title: String, detail: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Circle().fill(color).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
    }
}

private struct IntakeStatusView: View {
    let scannedCode: ParsedScan?
    let scan: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(scannedCode == nil ? "Ready to scan" : "Code captured", systemImage: scannedCode == nil ? "barcode.viewfinder" : "checkmark.circle")
        } description: {
            if let scannedCode {
                Text(scannedCode.normalizedGTIN ?? scannedCode.raw)
            } else {
                Text("Point the camera at a UPC, EAN, QR, or GS1 code on one donated item.")
            }
        } actions: {
            Button(scannedCode == nil ? "Open scanner" : "Scan another", action: scan)
                .buttonStyle(.borderedProminent)
        }
    }
}
