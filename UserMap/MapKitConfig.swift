import Foundation

enum MapKitConfig {
    /// Локальный ключ лежит в `MapKitSecrets.plist` (файл не коммитится).
    /// Шаблон: `MapKitSecrets.example.plist`.
    static var apiKey: String {
        guard
            let url = Bundle.main.url(forResource: "MapKitSecrets", withExtension: "plist"),
            let values = NSDictionary(contentsOf: url),
            let key = values["APIKey"] as? String
        else {
            return "YOUR_API_KEY"
        }
        return key
    }

    static var isConfigured: Bool {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return !key.isEmpty && key != "YOUR_API_KEY"
    }
}
