# iOS client foundation

`FoodDonationCore` is the first native client layer for the iOS 20 app. It contains:

- API request/response models matching the `/v1` server contract;
- actor-isolated API access with role and idempotency headers;
- UPC/EAN/GTIN validation and initial GS1 parsing;
- a durable offline mutation outbox for later synchronization.

Run the platform-independent tests with:

```bash
swift run --build-system native FoodDonationCoreChecks
```

The native build-system flag works around a SwiftPM/XCBuild property-list failure in the currently selected standalone Command Line Tools. The next client slice adds the SwiftUI app target, VisionKit camera capture, on-device text recognition, and SwiftData persistence. Full iPhone simulator builds require Xcode; only Command Line Tools are currently selected on this machine.
