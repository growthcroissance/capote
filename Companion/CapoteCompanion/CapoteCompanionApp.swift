import SwiftUI

@main
struct CapoteCompanionApp: App {
    @StateObject private var model = CompanionModel()

    var body: some Scene {
        WindowGroup {
            CompanionContentView(model: model)
        }
    }
}
