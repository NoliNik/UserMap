import CoreTransferable
import Foundation
import UniformTypeIdentifiers

extension UTType {
    static var userMapRide: UTType {
        UTType(exportedAs: "nolinik.UserMap.ride")
    }
}

struct RideFile: Codable, Sendable {
    var version: Int
    var ride: Ride
}

enum RideShare {
    static let fileExtension = "usermap"

    static func data(for ride: Ride) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(RideFile(version: 1, ride: ride))
    }

    static func ride(from data: Data) throws -> Ride {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let file = try? decoder.decode(RideFile.self, from: data) {
            return file.ride
        }
        return try decoder.decode(Ride.self, from: data)
    }

    static func read(from url: URL) throws -> Ride {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let data = try Data(contentsOf: url)
        return try ride(from: data)
    }
}

extension Ride: Transferable {
    var exportFileName: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return "zaezd-\(formatter.string(from: startedAt)).\(RideShare.fileExtension)"
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .userMapRide) { ride in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(ride.exportFileName)
            try RideShare.data(for: ride).write(to: url, options: .atomic)
            return SentTransferredFile(url)
        } importing: { received in
            var ride = try RideShare.read(from: received.file)
            ride.id = UUID()
            if ride.endedAt == nil {
                ride.endedAt = ride.points.last?.timestamp ?? ride.startedAt
            }
            return ride
        }
    }
}
