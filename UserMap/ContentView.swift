import SwiftUI

struct ContentView: View {
    @Binding var pendingImportURL: URL?

    var body: some View {
        if MapKitConfig.isConfigured {
            MapScreen(pendingImportURL: $pendingImportURL)
        } else {
            APIKeySetupView()
        }
    }
}

private struct MapScreen: View {
    @Binding var pendingImportURL: URL?
    @Environment(\.scenePhase) private var scenePhase
    @State private var session = MapSession()
    @State private var showHistory = false
    @State private var importFailed = false

    var body: some View {
        ZStack {
            YandexMapView(mapView: session.mapView)
                .ignoresSafeArea()

            VStack {
                statsCard
                if session.displayedRideID != nil {
                    Button(action: session.hideDisplayedRide) {
                        Text("Скрыть прошлый трек")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                }
                Spacer()
                bottomControls
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .onAppear {
            session.start()
            importPendingRideIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                session.requestLocationAccess()
            }
        }
        .onChange(of: pendingImportURL) { _, _ in
            importPendingRideIfNeeded()
        }
        .alert("Не удалось открыть заезд", isPresented: $importFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Файл повреждён или это не трек UserMap.")
        }
        .sheet(isPresented: $showHistory) {
            RideHistoryView(
                rides: session.rides.filter(\.isFinished),
                selectedRideID: session.displayedRideID,
                onSelect: { ride in
                    session.showRide(ride)
                    showHistory = false
                },
                onDelete: session.deleteRide,
                onImport: { url in
                    showHistory = false
                    if session.importRide(from: url) == nil {
                        importFailed = true
                    }
                }
            )
            .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder
    private var statsCard: some View {
        if session.locationStatus == .denied {
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Нет доступа к геолокации. Открыть Настройки")
                    .font(.footnote)
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
        } else if session.isRecording || session.liveRide != nil {
            RideStatsCard(
                isRecording: session.isRecording,
                distanceMeters: session.liveRide?.distanceMeters ?? 0,
                ascentMeters: session.liveRide?.ascentMeters ?? 0,
                descentMeters: session.liveRide?.descentMeters ?? 0,
                altitudeMeters: session.liveRide?.points.last?.altitude,
                startedAt: session.liveRide?.startedAt ?? .now,
                endedAt: session.liveRide?.endedAt,
                speedKmh: session.currentSpeedKmh
            )
        } else if let statusText {
            Text(statusText)
                .font(.footnote.monospaced())
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
        }
    }

    private var bottomControls: some View {
        HStack(alignment: .bottom) {
            roundButton(systemName: "list.bullet") {
                showHistory = true
            }
            .accessibilityLabel("Заезды")

            Spacer()

            Button(action: session.toggleRecording) {
                Image(systemName: session.isRecording ? "stop.fill" : "record.circle")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(session.isRecording ? Color.white : Color.red)
                    .frame(width: 72, height: 72)
                    .background(session.isRecording ? Color.red : Color.white.opacity(0.92), in: Circle())
            }
            .accessibilityLabel(session.isRecording ? "Остановить запись" : "Начать запись")
            .disabled(session.locationStatus == .denied)

            Spacer()

            VStack(spacing: 10) {
                roundButton(systemName: "plus", action: session.zoomIn)
                    .accessibilityLabel("Приблизить")
                roundButton(systemName: "minus", action: session.zoomOut)
                    .accessibilityLabel("Отдалить")
                roundButton(systemName: "location.fill", action: session.centerOnUser)
                    .accessibilityLabel("Моё местоположение")
            }
        }
        .foregroundStyle(.primary)
    }

    private func roundButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title3.weight(.semibold))
                .frame(width: 52, height: 52)
                .background(.ultraThinMaterial, in: Circle())
        }
    }

    private func importPendingRideIfNeeded() {
        guard let url = pendingImportURL else { return }
        pendingImportURL = nil
        if session.importRide(from: url) == nil {
            importFailed = true
        }
    }

    private var statusText: String? {
        switch session.locationStatus {
        case .available:
            return session.coordinateText
        case .requesting:
            return "Запрашиваем геолокацию…"
        case .failed(let message):
            return message
        case .idle, .denied:
            return nil
        }
    }
}

private struct RideStatsCard: View {
    let isRecording: Bool
    let distanceMeters: Double
    let ascentMeters: Double
    let descentMeters: Double
    let altitudeMeters: Double?
    let startedAt: Date
    let endedAt: Date?
    let speedKmh: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 12) {
                HStack(spacing: 16) {
                    stat("Дистанция", RideFormat.distance(distanceMeters))
                    stat("Время", RideFormat.duration(max(0, (endedAt ?? context.date).timeIntervalSince(startedAt))))
                    stat("Скорость", RideFormat.speed(speedKmh))
                }
                HStack(spacing: 16) {
                    stat("Подъём", RideFormat.elevation(ascentMeters))
                    stat("Спуск", RideFormat.elevation(descentMeters))
                    stat("Высота", RideFormat.altitude(altitudeMeters))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
            .overlay(alignment: .topLeading) {
                if isRecording {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(.red)
                            .frame(width: 8, height: 8)
                        Text("Запись")
                            .font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .offset(x: 12, y: -10)
                }
            }
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct APIKeySetupView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Нужен ключ Яндекс MapKit")
                .font(.title2.bold())

            Text("Карта не запустится без API-ключа. Получите его и вставьте в `MapKitConfig.swift`.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                labeledStep("1", "Откройте developer.tech.yandex.ru")
                labeledStep("2", "Подключите MapKit Mobile SDK")
                labeledStep("3", "Скопируйте ключ в MapKitConfig.apiKey")
            }
            .padding(.top, 8)

            Link("Кабинет разработчика Яндекса", destination: URL(string: "https://developer.tech.yandex.ru/")!)
                .padding(.top, 8)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func labeledStep(_ number: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(number)
                .font(.headline)
                .foregroundStyle(.tint)
                .frame(width: 18, alignment: .leading)
            Text(text)
        }
    }
}

#Preview {
    ContentView(pendingImportURL: .constant(nil))
}
