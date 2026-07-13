import SwiftUI

@main
struct DNSConnectorApp: App {
    @StateObject private var viewModel = DNSViewModel()

    var body: some Scene {
        MenuBarExtra("NKriZ DNS", systemImage: viewModel.menuBarSymbol) {
            DNSMenuView()
                .environmentObject(viewModel)
        }
        .menuBarExtraStyle(.menu)
    }
}
