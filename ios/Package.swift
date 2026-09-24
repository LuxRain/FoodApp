// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FoodDonationCore",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "FoodDonationCore", targets: ["FoodDonationCore"]),
        .executable(name: "FoodDonationCoreChecks", targets: ["FoodDonationCoreChecks"]),
    ],
    targets: [
        .target(name: "FoodDonationCore"),
        .executableTarget(name: "FoodDonationCoreChecks", dependencies: ["FoodDonationCore"]),
    ]
)
