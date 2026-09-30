import SwiftUI
import UniformTypeIdentifiers

struct RideHistoryView: View {
    let rides: [Ride]
    var selectedRideID: UUID?
    let onSelect: (Ride) -> Void
    let onDelete: (Ride) -> Void
    var onImport: ((URL) -> Void)?

    @State private var showImporter = false

    var body: some View {
        NavigationStack {
            Group {
                if rides.isEmpty {
                    ContentUnavailableView(
                        "Пока нет заездов",
                        systemImage: "map",
                        description: Text("Нажмите запись на карте, проедьте участок и остановите трек. Или импортируйте чужой файл .usermap.")
                    )
                } else {
                    List {
                        ForEach(rides) { ride in
                            HStack {
                                Button {
                                    onSelect(ride)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(ride.title)
                                                .foregroundStyle(.primary)
                                            Text("\(RideFormat.distance(ride.distanceMeters)) · \(RideFormat.duration(ride.duration())) · ↑\(RideFormat.elevation(ride.ascentMeters)) · ↓\(RideFormat.elevation(ride.descentMeters))")
                                                .font(.footnote)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if selectedRideID == ride.id {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.blue)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)

                                ShareLink(
                                    item: ride,
                                    preview: SharePreview(ride.title, image: Image(systemName: "motorcycle.fill"))
                                ) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.body.weight(.semibold))
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Поделиться заездом")
                            }
                        }
                        .onDelete { indexSet in
                            indexSet.map { rides[$0] }.forEach(onDelete)
                        }
                    }
                }
            }
            .navigationTitle("Заезды")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Импорт", systemImage: "square.and.arrow.down") {
                        showImporter = true
                    }
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.userMapRide, .json]
            ) { result in
                guard case .success(let url) = result else { return }
                onImport?(url)
            }
        }
    }
}
