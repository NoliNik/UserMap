import CoreLocation
import UIKit
import YandexMapsMobile

@Observable
final class MapSession: NSObject {
    enum LocationStatus: Equatable {
        case idle
        case requesting
        case available
        case denied
        case failed(String)
    }

    let mapView: YMKMapView
    private(set) var locationStatus: LocationStatus = .idle
    private(set) var coordinateText: String?
    private(set) var isRecording = false
    private(set) var currentSpeedKmh: Double?
    private(set) var liveRide: Ride?
    private(set) var rides: [Ride] = []
    private(set) var displayedRideID: UUID?

    private let locationManager = CLLocationManager()
    private let store = RideStore.shared
    private var userLocationLayer: YMKUserLocationLayer?
    private var liveCollection: YMKMapObjectCollection?
    private var historyCollection: YMKMapObjectCollection?
    private var livePolyline: YMKPolylineMapObject?
    private var historyPolyline: YMKPolylineMapObject?
    private var lastAcceptedLocation: CLLocation?
    private var didCenterOnUser = false
    private var pointsSinceSave = 0

    override init() {
        mapView = Self.makeMapView()
        super.init()

        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.activityType = .otherNavigation
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.distanceFilter = kCLDistanceFilterNone

        rides = store.load().compactMap { ride in
            if ride.isFinished { return ride }
            guard ride.points.count >= 2 else { return nil }
            var finished = ride
            finished.endedAt = ride.points.last?.timestamp ?? ride.startedAt
            return finished
        }
        store.save(rides)

        moveCamera(to: Self.fallbackPoint, zoom: 10, animated: false)
    }

    func start() {
        setupUserLocationLayer()
        setupTrackCollection()
        requestLocationAccess()
    }

    func requestLocationAccess() {
        applyAuthorization(locationManager.authorizationStatus)
    }

    func zoomIn() {
        adjustZoom(by: 1)
    }

    func zoomOut() {
        adjustZoom(by: -1)
    }

    func centerOnUser() {
        if let camera = userLocationLayer?.cameraPosition() {
            moveCamera(to: camera.target, zoom: max(camera.zoom, 16), animated: true)
            return
        }

        if let location = locationManager.location {
            center(on: location, animated: true)
            return
        }

        requestLocationAccess()
    }

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func startRecording() {
        guard !isRecording else { return }
        guard locationStatus == .available else {
            requestLocationAccess()
            return
        }

        if locationManager.authorizationStatus == .authorizedWhenInUse {
            locationManager.requestAlwaysAuthorization()
        }

        liveRide = Ride()
        lastAcceptedLocation = nil
        pointsSinceSave = 0
        isRecording = true
        enableBackgroundUpdates(true)
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.startUpdatingLocation()
        clearLiveTrack()

        if let location = locationManager.location, shouldAccept(location) {
            append(location)
        }
    }

    func stopRecording() {
        guard isRecording, var ride = liveRide else { return }

        isRecording = false
        enableBackgroundUpdates(false)
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = kCLDistanceFilterNone

        ride.endedAt = ride.points.last?.timestamp ?? .now
        if ride.points.count >= 2 {
            upsert(ride)
            liveRide = ride
        } else {
            rides.removeAll { $0.id == ride.id }
            store.save(rides)
            liveRide = nil
            clearLiveTrack()
        }
    }

    func showRide(_ ride: Ride) {
        if displayedRideID == ride.id {
            hideDisplayedRide()
            return
        }

        displayedRideID = ride.id
        drawHistory(points: ride.points.map(\.ymkPoint), fit: true)
    }

    func hideDisplayedRide() {
        displayedRideID = nil
        historyPolyline = nil
        historyCollection?.clear()
    }

    @discardableResult
    func importRide(from url: URL) -> Ride? {
        guard var ride = try? RideShare.read(from: url), ride.points.count >= 2 else {
            return nil
        }

        ride.id = UUID()
        if ride.endedAt == nil {
            ride.endedAt = ride.points.last?.timestamp ?? ride.startedAt
        }
        rides.insert(ride, at: 0)
        store.save(rides)
        showRide(ride)
        return ride
    }

    func deleteRide(_ ride: Ride) {
        rides.removeAll { $0.id == ride.id }
        store.save(rides)
        if displayedRideID == ride.id {
            hideDisplayedRide()
        }
        if liveRide?.id == ride.id, !isRecording {
            liveRide = nil
            clearLiveTrack()
        }
    }

    private func setupUserLocationLayer() {
        guard userLocationLayer == nil else { return }

        let layer = YMKMapKit.sharedInstance().createUserLocationLayer(with: mapView.mapWindow)
        layer.setVisibleWithOn(true)
        layer.isHeadingModeActive = false
        layer.setDefaultSource()
        layer.setObjectListenerWith(self)
        userLocationLayer = layer
    }

    private func setupTrackCollection() {
        if liveCollection == nil {
            liveCollection = mapView.mapWindow.map.mapObjects.add()
        }
        if historyCollection == nil {
            historyCollection = mapView.mapWindow.map.mapObjects.add()
        }
    }

    private func applyAuthorization(_ status: CLAuthorizationStatus) {
        switch status {
        case .notDetermined:
            locationStatus = .requesting
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            locationStatus = .available
            locationManager.startUpdatingLocation()
            if isRecording {
                enableBackgroundUpdates(true)
            }
        case .denied, .restricted:
            locationStatus = .denied
            if isRecording {
                stopRecording()
            }
            locationManager.stopUpdatingLocation()
        @unknown default:
            locationStatus = .denied
        }
    }

    private func enableBackgroundUpdates(_ enabled: Bool) {
        locationManager.allowsBackgroundLocationUpdates = enabled
        locationManager.showsBackgroundLocationIndicator = enabled
    }

    private func append(_ location: CLLocation) {
        guard var ride = liveRide else { return }

        ride.points.append(RidePoint(location))
        ride.distanceMeters = Self.distance(of: ride.points)
        lastAcceptedLocation = location
        liveRide = ride
        currentSpeedKmh = location.speed >= 0 ? location.speed * 3.6 : currentSpeedKmh
        drawLive(points: ride.points.map(\.ymkPoint))

        pointsSinceSave += 1
        if pointsSinceSave >= 10 {
            pointsSinceSave = 0
            upsert(ride)
        }
    }

    private func upsert(_ ride: Ride) {
        if let index = rides.firstIndex(where: { $0.id == ride.id }) {
            rides[index] = ride
        } else {
            rides.insert(ride, at: 0)
        }
        store.save(rides)
    }

    private func shouldAccept(_ location: CLLocation) -> Bool {
        // На симуляторе accuracy часто -1 или > 40 м — из-за этого трек не рос.
        if location.horizontalAccuracy > 150 { return false }
        guard let last = lastAcceptedLocation else { return true }

        let distance = location.distance(from: last)
        if distance < 2 { return false }

        // Отсекаем только явные телепорты, не симуляторный City Run.
        let dt = location.timestamp.timeIntervalSince(last.timestamp)
        if dt > 0, dt < 2, distance > 2500 { return false }
        return true
    }

    private static func distance(of points: [RidePoint]) -> CLLocationDistance {
        guard points.count >= 2 else { return 0 }
        return zip(points, points.dropFirst()).reduce(0) { total, pair in
            total + pair.0.clLocation.distance(from: pair.1.clLocation)
        }
    }

    private func drawLive(points: [YMKPoint]) {
        setupTrackCollection()
        guard let collection = liveCollection, points.count >= 2 else { return }
        updatePolyline(
            &livePolyline,
            in: collection,
            points: points,
            color: UIColor.systemOrange,
            width: 6
        )
    }

    private func drawHistory(points: [YMKPoint], fit: Bool) {
        setupTrackCollection()
        guard let collection = historyCollection, points.count >= 2 else {
            hideDisplayedRide()
            return
        }

        let polyline = updatePolyline(
            &historyPolyline,
            in: collection,
            points: points,
            color: UIColor.systemBlue.withAlphaComponent(0.85),
            width: 5
        )

        if fit {
            let geometry = YMKGeometry(polyline: polyline)
            let position = mapView.mapWindow.map.cameraPosition(with: geometry)
            mapView.mapWindow.map.move(
                with: position,
                animation: YMKAnimation(type: .smooth, duration: 0.6)
            )
        }
    }

    @discardableResult
    private func updatePolyline(
        _ polylineObject: inout YMKPolylineMapObject?,
        in collection: YMKMapObjectCollection,
        points: [YMKPoint],
        color: UIColor,
        width: Float
    ) -> YMKPolyline {
        let polyline = YMKPolyline(points: points)
        if let polylineObject {
            polylineObject.geometry = polyline
        } else {
            collection.clear()
            let object = collection.addPolyline(with: polyline)
            object.strokeWidth = width
            object.setStrokeColorWith(color)
            object.outlineWidth = 1.5
            object.outlineColor = UIColor.black.withAlphaComponent(0.35)
            polylineObject = object
        }
        return polyline
    }

    private func clearLiveTrack() {
        livePolyline = nil
        liveCollection?.clear()
    }

    private func center(on location: CLLocation, animated: Bool) {
        coordinateText = String(
            format: "%.5f, %.5f",
            location.coordinate.latitude,
            location.coordinate.longitude
        )
        moveCamera(
            to: YMKPoint(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            ),
            zoom: 16,
            animated: animated
        )
    }

    private func adjustZoom(by delta: Float) {
        let current = mapView.mapWindow.map.cameraPosition
        let zoom = min(21, max(2, current.zoom + delta))
        guard abs(zoom - current.zoom) > 0.01 else { return }

        mapView.mapWindow.map.move(
            with: YMKCameraPosition(
                target: current.target,
                zoom: zoom,
                azimuth: current.azimuth,
                tilt: current.tilt
            ),
            animation: YMKAnimation(type: .smooth, duration: 0.2)
        )
    }

    private func moveCamera(to point: YMKPoint, zoom: Float, animated: Bool) {
        let position = YMKCameraPosition(target: point, zoom: zoom, azimuth: 0, tilt: 0)
        if animated {
            mapView.mapWindow.map.move(
                with: position,
                animation: YMKAnimation(type: .smooth, duration: 0.6)
            )
        } else {
            mapView.mapWindow.map.move(with: position)
        }
    }

    private static func makeMapView() -> YMKMapView {
        #if targetEnvironment(simulator)
        YMKMapView(frame: .zero, vulkanPreferred: true, transparencySupport: false)!
        #else
        YMKMapView(frame: .zero)!
        #endif
    }

    private static let fallbackPoint = YMKPoint(latitude: 55.751244, longitude: 37.618423)

    static func motorcycleIcon() -> UIImage {
        let config = UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)
        guard let symbol = (
            UIImage(systemName: "motorcycle.fill", withConfiguration: config)
                ?? UIImage(systemName: "bicycle", withConfiguration: config)
        )?.withTintColor(.white, renderingMode: .alwaysOriginal) else {
            return UIImage()
        }

        let side: CGFloat = 26
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        return renderer.image { ctx in
            let rect = CGRect(x: 0, y: 0, width: side, height: side).insetBy(dx: 0.5, dy: 0.5)
            UIColor.systemOrange.setFill()
            UIBezierPath(ovalIn: rect).fill()
            UIColor.black.withAlphaComponent(0.28).setStroke()
            let border = UIBezierPath(ovalIn: rect)
            border.lineWidth = 1
            border.stroke()

            ctx.cgContext.translateBy(x: side / 2, y: side / 2)
            ctx.cgContext.rotate(by: -.pi / 2)
            symbol.draw(at: CGPoint(x: -symbol.size.width / 2, y: -symbol.size.height / 2))
        }
    }
}

extension MapSession: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        applyAuthorization(manager.authorizationStatus)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        coordinateText = String(
            format: "%.5f, %.5f",
            location.coordinate.latitude,
            location.coordinate.longitude
        )
        locationStatus = .available

        if location.speed >= 0 {
            currentSpeedKmh = location.speed * 3.6
        }

        if !didCenterOnUser {
            didCenterOnUser = true
            center(on: location, animated: true)
        }

        guard isRecording else { return }
        for sample in locations {
            if shouldAccept(sample) {
                append(sample)
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if locationStatus != .denied {
            locationStatus = .failed(error.localizedDescription)
        }
    }
}

extension MapSession: YMKUserLocationObjectListener {
    func onObjectAdded(with view: YMKUserLocationView) {
        let icon = Self.motorcycleIcon()
        let style = YMKIconStyle()
        style.anchor = NSValue(cgPoint: CGPoint(x: 0.5, y: 0.5))
        style.rotationType = NSNumber(value: YMKRotationType.rotate.rawValue)
        style.flat = true
        style.scale = 1

        view.arrow.setIconWith(icon, style: style)
        view.pin.setIconWith(icon, style: style)
        view.accuracyCircle.fillColor = UIColor.systemOrange.withAlphaComponent(0.12)
        view.accuracyCircle.strokeColor = UIColor.systemOrange.withAlphaComponent(0.35)
        view.accuracyCircle.strokeWidth = 1
    }

    func onObjectRemoved(with view: YMKUserLocationView) {}

    func onObjectUpdated(with view: YMKUserLocationView, event: YMKObjectEvent) {}
}

private extension RidePoint {
    var ymkPoint: YMKPoint {
        YMKPoint(latitude: latitude, longitude: longitude)
    }
}
