import Foundation

final class RideStore {
    static let shared = RideStore()

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("UserMap", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("rides.json")

        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> [Ride] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? decoder.decode([Ride].self, from: data)) ?? []
    }

    func save(_ rides: [Ride]) {
        guard let data = try? encoder.encode(rides) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
