import AVFoundation
import SwiftUI
import VisionKit

struct ScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var scannerAvailable = DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    @State private var showingManualEntry = false
    @State private var manualCode = "012345678905"
    let onScan: (String) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if scannerAvailable {
                    BarcodeScannerView(onScan: onScan)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    ContentUnavailableView {
                        Label("Scanner unavailable", systemImage: "camera.fill")
                    } description: {
                        Text("Use a physical supported iPhone, or enter the development barcode manually.")
                    } actions: {
                        Button("Enter barcode") { showingManualEntry = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("Scan package")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if scannerAvailable {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Type code") { showingManualEntry = true }
                    }
                }
            }
        }
        .alert("Enter barcode", isPresented: $showingManualEntry) {
            TextField("UPC, EAN, or GTIN", text: $manualCode)
                .keyboardType(.numberPad)
            Button("Cancel", role: .cancel) {}
            Button("Look up") { onScan(manualCode) }
        } message: {
            Text("The seeded development barcode is already filled in.")
        }
    }
}

private struct BarcodeScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [
                .barcode(symbologies: [
                    .ean8,
                    .ean13,
                    .upce,
                    .code128,
                    .qr,
                    .gs1DataBar,
                    .gs1DataBarExpanded,
                    .gs1DataBarLimited
                ])
            ],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: true,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        guard !scanner.isScanning else { return }
        try? scanner.startScanning()
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onScan: (String) -> Void
        private var completed = false

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            guard !completed else { return }
            guard case let .barcode(barcode) = addedItems.first,
                  let payload = barcode.payloadStringValue,
                  !payload.isEmpty else { return }
            completed = true
            dataScanner.stopScanning()
            onScan(payload)
        }
    }
}
