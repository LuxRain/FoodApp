// swift-tools-version: 6.2

import PackageDescription
import AppleProductTypes

let package = Package(
    name: "FoodDonationApp",
    platforms: [.iOS(.v18)],
    products: [
        .iOSApplication(
            name: "Food Donation",
            targets: ["FoodDonationApp"],
            bundleIdentifier: "com.linminpei.fooddonation",
            displayVersion: "0.1.0",
            bundleVersion: "1",
            appIcon: .placeholder(icon: .carrot),
            accentColor: .presetColor(.green),
            supportedDeviceFamilies: [.phone],
            supportedInterfaceOrientations: [.portrait],
            capabilities: [
                .camera(purposeString: "Scan donated food barcodes and capture package evidence."),
                .outgoingNetworkConnections()
            ]
        )
    ],
    dependencies: [
        .package(path: "..")
    ],
    targets: [
        .executableTarget(
            name: "FoodDonationApp",
            dependencies: [
                .product(name: "FoodDonationCore", package: "ios")
            ],
            path: "Sources"
        )
    ]
)
