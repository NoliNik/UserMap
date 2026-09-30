import SwiftUI
import YandexMapsMobile

@main
struct UserMapApp: App {
    @State private var pendingImportURL: URL?

    init() {
        guard MapKitConfig.isConfigured else { return }
        YMKMapKit.setApiKey(MapKitConfig.apiKey)
        YMKMapKit.setLocale("ru_RU")
        _ = YMKMapKit.sharedInstance()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(pendingImportURL: $pendingImportURL)
                .onOpenURL { pendingImportURL = $0 }
        }
    }
}
