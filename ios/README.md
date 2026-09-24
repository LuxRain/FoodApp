# iOS client foundation

`FoodDonationCore` is the first native client layer for the iOS 18+ app. It contains:

- API request/response models matching the `/v1` server contract;
- actor-isolated API access with role and idempotency headers;
- UPC/EAN/GTIN validation and initial GS1 parsing;
- a durable offline mutation outbox for later synchronization.

Run the platform-independent tests with:

```bash
swift run --build-system native FoodDonationCoreChecks
```

The native build-system flag works around a SwiftPM/XCBuild property-list failure in the currently selected standalone Command Line Tools. The next client slice adds the SwiftUI app target, VisionKit camera capture, on-device text recognition, and SwiftData persistence. Full iPhone simulator builds require Xcode; only Command Line Tools are currently selected on this machine.

## SwiftUI app

`FoodDonationApp.swiftpm` is the runnable iPhone application package. It currently provides:

- an expiration-first dashboard shell;
- a VisionKit barcode scanner for UPC/EAN, Code 128, QR, and GS1 DataBar symbols;
- normalization through `FoodDonationCore.ScanParser`;
- a native fallback state when scanning is unavailable, including in the simulator.

Open `FoodDonationApp.swiftpm` in Xcode, choose an iPhone or simulator, and run the `FoodDonationApp` scheme. The first physical-device run requires camera permission and ordinary Apple code signing.

Build from the command line without changing the global developer directory:

```bash
cd ios/FoodDonationApp.swiftpm
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -scheme FoodDonationApp \
  -destination "generic/platform=iOS Simulator" \
  build
```
