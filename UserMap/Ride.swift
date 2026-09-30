import CoreLocation
import Foundation

struct RidePoint: Codable, Hashable, Sendable {
    var latitude: Double
    var longitude: Double
    var altitude: Double
    var speed: Double
    var timestamp: Date
    var horizontalAccuracy: Double

    init(_ location: CLLocation) {
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        altitude = location.altitude
        speed = location.speed
        timestamp = location.timestamp
        horizontalAccuracy = location.horizontalAccuracy
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var clLocation: CLLocation {
        CLLocation(
            coordinate: coordinate,
            altitude: altitude,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: -1,
            course: -1,
            speed: speed,
            timestamp: timestamp
        )
    }
}

struct Ride: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var startedAt: Date
    var endedAt: Date?
    var distanceMeters: Double
    var points: [RidePoint]

    init(
        id: UUID = UUID(),
        startedAt: Date = .now,
        endedAt: Date? = nil,
        distanceMeters: Double = 0,
        points: [RidePoint] = []
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.distanceMeters = distanceMeters
        self.points = points
    }

    var isFinished: Bool { endedAt != nil }

    func duration(at date: Date = .now) -> TimeInterval {
        max(0, (endedAt ?? date).timeIntervalSince(startedAt))
    }

    var title: String {
        startedAt.formatted(date: .abbreviated, time: .shortened)
    }

    var ascentMeters: Double { elevation.ascent }
    var descentMeters: Double { elevation.descent }

    private var elevation: (ascent: Double, descent: Double) {
        Self.elevation(of: points)
    }

    static func elevation(of points: [RidePoint], threshold: Double = 8) -> (ascent: Double, descent: Double) {
        guard var lastAltitude = points.first?.altitude else { return (0, 0) }
        var ascent = 0.0
        var descent = 0.0

        for point in points.dropFirst() {
            let delta = point.altitude - lastAltitude
            if abs(delta) < threshold { continue }
            if abs(delta) > 80 {
                lastAltitude = point.altitude
                continue
            }
            if delta > 0 {
                ascent += delta
            } else {
                descent += -delta
            }
            lastAltitude = point.altitude
        }

        return (ascent, descent)
    }
}

enum RideFormat {
    static func distance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.2f км", meters / 1000)
        }
        return String(format: "%.0f м", meters)
    }

    static func duration(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    static func speed(_ kmh: Double?) -> String {
        guard let kmh, kmh >= 0 else { return "—" }
        return String(format: "%.0f км/ч", kmh)
    }

    static func elevation(_ meters: Double) -> String {
        String(format: "%.0f м", meters)
    }

    static func altitude(_ meters: Double?) -> String {
        guard let meters else { return "—" }
        return String(format: "%.0f м", meters)
    }
}
