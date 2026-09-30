import SwiftUI
import YandexMapsMobile

struct YandexMapView: UIViewRepresentable {
    let mapView: YMKMapView

    func makeUIView(context: Context) -> YMKMapView {
        mapView
    }

    func updateUIView(_ uiView: YMKMapView, context: Context) {}
}
