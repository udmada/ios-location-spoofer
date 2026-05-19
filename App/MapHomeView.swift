import SwiftUI
import MapKit
import NetworkExtension
import os.log

struct MapHomeView: View {
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074),
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
    )
    @State private var searchText: String = ""
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var selectedLocationName: String?
    @State private var showLocationSheet = false
    @State private var showRestartLocationGuide = false
    @State private var showDisableGuide = false
    @State private var currentLocationName: String = UserDefaults.standard.string(forKey: "currentLocationName") ?? ""
    @State private var vpnConnected: Bool = false
    @State private var vpnStatus: NEVPNStatus = .invalid

    private var isSpoofing: Bool {
        !currentLocationName.isEmpty && vpnConnected
    }

    var body: some View {
        ZStack(alignment: .top) {
            // 全屏地图
            MapReader { proxy in
                Map(position: $cameraPosition) {
                    if let coord = selectedCoordinate {
                        Marker("目标位置", coordinate: coord)
                            .tint(.red)
                    }
                }
                .ignoresSafeArea()
                .onTapGesture { tapLocation in
                    if let coordinate = proxy.convert(tapLocation, from: .local) {
                        selectCoordinate(coordinate)
                    }
                }
            }

            // 顶部状态条
            VStack {
                statusBar
                Spacer().allowsHitTesting(false)
            }
            .allowsHitTesting(true)

            // 底部搜索栏
            VStack {
                Spacer().allowsHitTesting(false)
                searchBar
            }
            .allowsHitTesting(true)

            // 右下角设置按钮(暂时隐藏,等设置页做出来再放出)
            /*
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    settingsButton
                        .padding(.trailing, 16)
                        .padding(.bottom, 90)
                }
            }
            */
        }
        .sheet(isPresented: $showLocationSheet) {
            locationSheet
                .presentationDetents([.height(220)])
        }
        .sheet(isPresented: $showRestartLocationGuide) {
            restartLocationGuide
        }
        .alert("关闭定位伪装", isPresented: $showDisableGuide) {
            Button("取消", role: .cancel) { }
            Button("关闭并重启", role: .destructive) {
                disableSpoofing()
            }
        } message: {
            Text("将关闭 VPN 并清除虚假定位。\n请在关闭后长按电源键重启手机,真实定位才会恢复。")
        }
        .onAppear {
            refreshVPNStatus()
            NotificationCenter.default.addObserver(forName: .NEVPNStatusDidChange, object: nil, queue: .main) { _ in
                refreshVPNStatus()
            }
        }
    }

    // MARK: - 子视图

    private var statusBar: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(isSpoofing ? Color.green : Color.gray)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(isSpoofing ? "伪装中" : (currentLocationName.isEmpty ? "未启用" : "未启用(VPN 已断开)"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                if !currentLocationName.isEmpty {
                    Text(currentLocationName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                }
            }

            Spacer()

            if !currentLocationName.isEmpty {
                Button(action: { showDisableGuide = true }) {
                    Text("关闭")
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.1))
                        .foregroundColor(.red)
                        .cornerRadius(6)
                }
            } else {
                Button(action: { connectVPN() }) {
                    Text(vpnConnected ? "VPN 已连" : "连接 VPN")
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(vpnConnected ? Color.green.opacity(0.1) : Color.blue.opacity(0.1))
                        .foregroundColor(vpnConnected ? .green : .blue)
                        .cornerRadius(6)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("搜索地点或点击地图选择", text: $searchText)
                .textFieldStyle(.plain)
                .submitLabel(.search)
                .onSubmit { performSearch() }
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.regularMaterial)
        .cornerRadius(12)
        .padding(.horizontal, 12)
        .padding(.bottom, 24)
    }

    private var settingsButton: some View {
        Button(action: { /* TODO: 设置页 */ }) {
            Image(systemName: "gearshape.fill")
                .font(.title2)
                .foregroundColor(.primary)
                .padding(12)
                .background(.regularMaterial)
                .clipShape(Circle())
        }
    }

    private var locationSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "mappin.circle.fill")
                    .foregroundColor(.red)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedLocationName ?? "未知位置")
                        .font(.headline)
                    if let coord = selectedCoordinate {
                        Text(String(format: "%.4f, %.4f", coord.latitude, coord.longitude))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }

            Spacer()

            Button(action: { setAsLocation() }) {
                Text("设为我的定位")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
        }
        .padding()
    }

    private var restartLocationGuide: some View {
        VStack(spacing: 20) {
            Text("最后一步")
                .font(.title2).fontWeight(.bold)
            Text("请关闭再打开定位服务")
                .font(.title3)
            VStack(alignment: .leading, spacing: 12) {
                Text("① 打开 iPhone「设置」").font(.body)
                Text("② 点击「隐私与安全性」").font(.body)
                Text("③ 点击「定位服务」").font(.body)
                Text("④ 关闭「定位服务」开关").font(.body)
                Text("⑤ 等待 3 秒").font(.body).foregroundColor(.red)
                Text("⑥ 重新打开「定位服务」开关").font(.body)
            }
            .padding()
            Spacer()
            Button("我已完成") {
                showRestartLocationGuide = false
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .padding(24)
    }

    // MARK: - 动作

    private func selectCoordinate(_ coordinate: CLLocationCoordinate2D) {
        selectedCoordinate = coordinate
        selectedLocationName = nil
        showLocationSheet = true

        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        geocoder.reverseGeocodeLocation(location) { placemarks, _ in
            if let placemark = placemarks?.first {
                let name = [placemark.name, placemark.locality, placemark.country]
                    .compactMap { $0 }
                    .joined(separator: ", ")
                DispatchQueue.main.async {
                    self.selectedLocationName = name.isEmpty ? "未知位置" : name
                }
            }
        }
    }

    private func performSearch() {
        guard !searchText.isEmpty else { return }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchText
        let search = MKLocalSearch(request: request)
        search.start { response, _ in
            if let item = response?.mapItems.first {
                let coord = item.placemark.coordinate
                DispatchQueue.main.async {
                    self.cameraPosition = .region(MKCoordinateRegion(
                        center: coord,
                        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                    ))
                    self.selectedCoordinate = coord
                    self.selectedLocationName = item.name
                    self.showLocationSheet = true
                }
            }
        }
    }

    private func setAsLocation() {
        guard let coord = selectedCoordinate else { return }
        let name = selectedLocationName ?? "未知位置"

        // GCJ-02 转 WGS-84
        let converted = CoordinateConverter.gcj02ToWgs84(lat: coord.latitude, lng: coord.longitude)
        LocationConfiguration.shared.setCoordinates(latitude: converted.latitude, longitude: converted.longitude)
        UserDefaults.standard.set(name, forKey: "currentLocationName")
        currentLocationName = name

        showLocationSheet = false

        // 弹出"重启定位服务"引导
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            showRestartLocationGuide = true
        }
    }

    private func disableSpoofing() {
        // 关 VPN
        if let manager = ContentView.vpnManager {
            manager.connection.stopVPNTunnel()
        }
        // 清坐标
        LocationConfiguration.shared.clearCoordinates()
        UserDefaults.standard.removeObject(forKey: "currentLocationName")
        currentLocationName = ""
    }

    private func connectVPN() {
        guard let manager = ContentView.vpnManager else { return }
        do {
            try manager.connection.startVPNTunnel()
        } catch {
            os_log("Failed to start VPN: %{public}@", error.localizedDescription)
        }
    }

    private func refreshVPNStatus() {
        if let manager = ContentView.vpnManager {
            vpnStatus = manager.connection.status
            vpnConnected = (vpnStatus == .connected)
        }
    }
}
