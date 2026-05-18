import SwiftUI
import MapKit

struct MapPickerView: View {
    @Binding var latitude: String
    @Binding var longitude: String
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    @State private var pin: CLLocationCoordinate2D? = nil
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            // 搜索框
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("搜索地名，如：杭州西湖", text: $searchText)
                    .onSubmit {
                        searchLocation()
                    }
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(10)
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(10)
            .padding(.horizontal)
            .padding(.top, 8)

            // 地图
            MapReader { proxy in
                Map(position: .constant(.region(region))) {
                    if let pin = pin {
                        Marker("目标位置", coordinate: pin)
                            .tint(.red)
                    }
                }
                .onTapGesture { position in
                    if let coordinate = proxy.convert(position, from: .local) {
                        pin = coordinate
                        latitude = String(format: "%.6f", coordinate.latitude)
                        longitude = String(format: "%.6f", coordinate.longitude)
                        region.center = coordinate
                    }
                }
            }
            .frame(height: 300)
            .cornerRadius(12)
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }

    private func searchLocation() {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchText
        let search = MKLocalSearch(request: request)
        search.start { response, error in
            guard let response = response, let item = response.mapItems.first else { return }
            let coord = item.placemark.coordinate
            pin = coord
            latitude = String(format: "%.6f", coord.latitude)
            longitude = String(format: "%.6f", coord.longitude)
            region = MKCoordinateRegion(
                center: coord,
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
        }
    }
}
