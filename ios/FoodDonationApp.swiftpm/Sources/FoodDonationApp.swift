import SwiftUI

@main
struct FoodDonationApp: App {
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--preview-sign-in") {
                NavigationStack {
                    SignInPreviewView()
                }
                .preferredColorScheme(.dark)
            } else {
                RootView()
            }
            #else
            RootView()
            #endif
        }
    }
}
