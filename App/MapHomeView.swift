import SwiftUI
import MapKit
import NetworkExtension
import Network

/// 诊断面板用:把 NEVPNStatus 映射成可读字符串(带 rawValue)。
private extension NEVPNStatus {
    var diagDesc: String {
        switch self {
        case .invalid: return "invalid(0)"
        case .disconnected: return "disconnected(1)"
        case .connecting: return "connecting(2)"
        case .connected: return "connected(3)"
        case .reasserting: return "reasserting(4)"
        case .disconnecting: return "disconnecting(5)"
        @unknown default: return "unknown"
        }
    }
}

struct MapHomeView: View {
    @State private var mapSelection: MapSelection<MKMapItem>?
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
    @State private var showRestartPhoneGuide = false
    @State private var currentLocationName: String = UserDefaults.standard.string(forKey: "currentLocationName") ?? ""
    @State private var vpnConnected: Bool = false
    @State private var vpnStatus: NEVPNStatus = .invalid
    @State private var savedLocations: [SavedLocation] = []
    @State private var recentLocations: [SavedLocation] = []
    @State private var showFavoritesSheet = false
    @State private var showSettings = false
    @State private var spoofingState: SpoofingState = .off
    @State private var justFavorited: Bool = false
    @State private var lastErrorReason: String = ""

    var body: some View {
        ZStack(alignment: .top) {
            // 全屏地图
            MapReader { proxy in
                Map(position: $cameraPosition, selection: $mapSelection) {
                    if let coord = selectedCoordinate {
                        Marker("目标位置", coordinate: coord)
                            .tint(.red)
                    }
                }
                .mapStyle(.standard(pointsOfInterest: .all))
                .mapFeatureSelectionAccessory(.automatic)
                .ignoresSafeArea()
                .onTapGesture(coordinateSpace: .global) { tapLocation in
                    // 空白点击才取坐标。注意:Map 的 POI 内置选中由 selection 绑定处理,
                    // 这个 onTapGesture 只在点击空白时触发(POI 点击会先被 Map 消化)
                    if let coordinate = proxy.convert(tapLocation, from: .global) {
                        selectCoordinate(coordinate)
                    }
                }
                .onChange(of: mapSelection) { _, newSelection in
                    handleMapSelection(newSelection)
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
        }
        .sheet(isPresented: $showLocationSheet) {
            locationSheet
                .presentationDetents([.height(220)])
        }
        .sheet(isPresented: $showRestartLocationGuide) {
            restartLocationGuide
        }
        .alert("关闭虚拟定位", isPresented: $showDisableGuide) {
            Button("取消", role: .cancel) { }
            Button("关闭", role: .destructive) {
                disableSpoofing()
            }
        } message: {
            Text("将关闭虚拟定位。关闭后请重启一次定位服务,真实定位才会恢复。")
        }
        .sheet(isPresented: $showRestartPhoneGuide) {
            disableRestartGuide
        }
        .sheet(isPresented: $showFavoritesSheet) {
            favoritesSheet
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .onAppear {
            refreshVPNStatus()
            loadSavedLocations()
            loadRecentLocations()
            // 根据当前数据恢复 spoofingState
            let savedName = UserDefaults.standard.string(forKey: "currentLocationName") ?? ""
            if !savedName.isEmpty && vpnConnected {
                spoofingState = .on(name: savedName)
            } else if !savedName.isEmpty && !vpnConnected {
                // 有坐标但 VPN 没连 → 等同 off
                spoofingState = .off
            } else {
                spoofingState = .off
            }
            NotificationCenter.default.addObserver(forName: .NEVPNStatusDidChange, object: nil, queue: .main) { _ in
                refreshVPNStatus()
            }
        }
    }

    // MARK: - 子视图

    private var statusBar: some View {
        HStack(spacing: 12) {
            // 圆点
            Circle()
                .fill(indicatorColor)
                .frame(width: 10, height: 10)

            // 文案
            VStack(alignment: .leading, spacing: 2) {
                Text(spoofingState.primaryText)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                if let sub = spoofingState.subText {
                    Text(sub)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // 主操作按钮
            actionButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private var indicatorColor: Color {
        switch spoofingState {
        case .off:      return .gray
        case .pending:  return .yellow
        case .on:       return .blue
        case .failed:   return .red
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch spoofingState {
        case .off:
            EmptyView()
        case .pending(_, let isClosing):
            Button(action: {
                // 取消 pending,根据 isClosing 决定回到哪个状态
                if isClosing {
                    // 取消关闭,恢复 on(如果还能找到原位置名)
                    let name = UserDefaults.standard.string(forKey: "currentLocationName") ?? ""
                    spoofingState = name.isEmpty ? .off : .on(name: name)
                } else {
                    // 取消开启
                    spoofingState = .off
                }
            }) {
                Text("取消")
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.gray.opacity(0.15))
                    .foregroundColor(.secondary)
                    .cornerRadius(6)
            }
        case .on:
            Button(action: { showDisableGuide = true }) {
                Text("关闭")
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.1))
                    .foregroundColor(.red)
                    .cornerRadius(6)
            }
        case .failed:
            Button(action: { spoofingState = .off }) {
                Text("重试")
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .cornerRadius(6)
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
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

            Button(action: { showFavoritesSheet = true }) {
                Image(systemName: "star.fill")
                    .font(.title3)
                    .foregroundColor(.yellow)
                    .padding(12)
                    .background(.regularMaterial)
                    .clipShape(Circle())
            }
            Button(action: { showSettings = true }) {
                Image(systemName: "gearshape.fill")
                    .font(.title3)
                    .foregroundColor(.primary)
                    .padding(12)
                    .background(.regularMaterial)
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 24)
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

            HStack(spacing: 12) {
                Button(action: { addCurrentSelectionToFavorites() }) {
                    HStack {
                        Image(systemName: justFavorited ? "checkmark.circle.fill" : "star")
                        Text(justFavorited ? "已收藏" : "收藏")
                            .fontWeight(justFavorited ? .semibold : .regular)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(justFavorited ? Color.green.opacity(0.15) : Color(UIColor.tertiarySystemBackground))
                    .foregroundColor(justFavorited ? Color.green : Color.primary)
                    .cornerRadius(12)
                    .animation(.easeInOut(duration: 0.2), value: justFavorited)
                }
                .disabled(justFavorited)
                Button(action: { setAsLocation() }) {
                    Text("设为定位")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
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
                // pending → on
                let name = UserDefaults.standard.string(forKey: "currentLocationName") ?? ""
                DiagLog.add("用户点【我已完成】:name=\(name),状态置 on,即将关 VPN")
                if !name.isEmpty {
                    spoofingState = .on(name: name)
                }
                // 定位已进系统缓存焊死,关 VPN 恢复全手机网络;伪装位置由 iOS 缓存维持,不受影响。
                // 状态卡 .on 独立于 vpnConnected(全局观察者只刷 vpnStatus/vpnConnected,不重置 spoofingState)。
                ContentView.vpnManager?.connection.stopVPNTunnel()
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

    private var disableRestartGuide: some View {
        VStack(spacing: 20) {
            Text("已关闭虚拟定位")
                .font(.title2).fontWeight(.bold)
            Text("最后一步:重启定位服务,真实定位才会恢复")
                .font(.title3)
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 12) {
                Text("请按以下步骤操作:")
                    .font(.body)
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
                showRestartPhoneGuide = false
                spoofingState = .off
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.green)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .padding(24)
    }

    private var favoritesSheet: some View {
        NavigationView {
            List {
                // 最近使用
                if !recentLocations.isEmpty {
                    Section("最近使用") {
                        ForEach(recentLocations) { saved in
                            Button(action: { selectFavorite(saved) }) {
                                favoriteRow(saved: saved, iconName: "clock", iconColor: .orange)
                            }
                        }
                    }
                }

                // 我的收藏
                Section("我的收藏") {
                    if savedLocations.isEmpty {
                        Text("还没有收藏的位置")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(savedLocations) { saved in
                            Button(action: { selectFavorite(saved) }) {
                                favoriteRow(saved: saved, iconName: "star.fill", iconColor: .yellow)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    deleteFavorite(saved)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("收藏的位置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { showFavoritesSheet = false }
                }
            }
        }
    }

    @ViewBuilder
    private func favoriteRow(saved: SavedLocation, iconName: String, iconColor: Color) -> some View {
        HStack {
            Image(systemName: iconName)
                .foregroundColor(iconColor)
            VStack(alignment: .leading) {
                Text(saved.name)
                    .foregroundColor(.primary)
                Text(String(format: "%.4f, %.4f", saved.latitude, saved.longitude))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
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

    private func handleMapSelection(_ selection: MapSelection<MKMapItem>?) {
        guard let selection else { return }

        // 自定义 Marker 走 .value;POI 走 .feature
        if let mapItem = selection.value {
            applyMapItem(mapItem)
            return
        }
        guard let feature = selection.feature else { return }

        // POI:用 MKMapItemRequest 异步换成 MKMapItem,取 name + coordinate
        Task { @MainActor in
            do {
                let mapItem = try await MKMapItemRequest(feature: feature).mapItem
                applyMapItem(mapItem)
            } catch {
                // 兜底:直接用 feature 自带字段
                applySelectedLocation(
                    name: feature.title ?? "未知地点",
                    coordinate: feature.coordinate
                )
            }
        }
    }

    private func applyMapItem(_ mapItem: MKMapItem) {
        applySelectedLocation(
            name: mapItem.name ?? "未知地点",
            coordinate: mapItem.placemark.coordinate
        )
    }

    private func applySelectedLocation(name: String, coordinate: CLLocationCoordinate2D) {
        selectedCoordinate = coordinate
        selectedLocationName = name
        showLocationSheet = true
        withAnimation {
            cameraPosition = .region(MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            ))
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
        DiagLog.add("设为定位入口:坐标=(\(coord.latitude), \(coord.longitude)) 名称=\(name) vpnConnected=\(vpnConnected) → 走\(vpnConnected ? "热切重启" : "冷启动")分支")

        // 进入 pending 状态(尚未生效)
        spoofingState = .pending(name: name, isClosing: false)

        // GCJ-02 转 WGS-84
        let converted = CoordinateConverter.gcj02ToWgs84(lat: coord.latitude, lng: coord.longitude)
        LocationConfiguration.shared.setCoordinates(latitude: converted.latitude, longitude: converted.longitude)
        UserDefaults.standard.set(name, forKey: "currentLocationName")
        currentLocationName = name
        DiagLog.add("已写入坐标(WGS-84)到 LocationConfiguration + UserDefaults")

        // 收藏/最近存原始 GCJ-02 坐标(用于显示和地图回显),设为定位时才在 setAsLocation 内转 WGS-84
        addToRecentLocations(name: name, latitude: coord.latitude, longitude: coord.longitude)

        // 检查 VPN 状态,需要时自动连
        if !vpnConnected {
            connectVPNForSpoofing { success, errorMsg in
                if success {
                    DiagLog.add("[冷启动] connectVPNForSpoofing 回调 success → 关 sheet,1 秒后弹教学")
                    // VPN 连上后,弹出"重启定位服务"教学
                    DispatchQueue.main.async {
                        showLocationSheet = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            showRestartLocationGuide = true
                            DiagLog.add("[冷启动] 已弹出重启定位服务教学")
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        DiagLog.add("[冷启动] connectVPNForSpoofing 回调 failure:\(errorMsg ?? "未知错误")")
                        // 失败,显示具体原因
                        spoofingState = .failed(reason: errorMsg ?? "未知错误")
                        showLocationSheet = false
                    }
                }
            }
        } else {
            // VPN 已连:无感重启 tunnel,让 Network Extension 重读新坐标。
            // 临时观察者驱动 stop→等disconnect→start→等connect 两阶段状态机,8 秒超时。
            showLocationSheet = false
            restartVPNForNewCoordinates()
        }
    }

    private func loadRecentLocations() {
        if let data = UserDefaults.standard.data(forKey: "recentLocations"),
           let decoded = try? JSONDecoder().decode([SavedLocation].self, from: data) {
            recentLocations = decoded
        }
    }

    private func saveRecentLocations() {
        if let encoded = try? JSONEncoder().encode(recentLocations) {
            UserDefaults.standard.set(encoded, forKey: "recentLocations")
        }
    }

    private func addToRecentLocations(name: String, latitude: Double, longitude: Double) {
        // 去重:相同 name 移到顶部
        recentLocations.removeAll { $0.name == name }
        let new = SavedLocation(name: name, latitude: latitude, longitude: longitude)
        recentLocations.insert(new, at: 0)
        // 限制最多 5 个
        if recentLocations.count > 5 {
            recentLocations = Array(recentLocations.prefix(5))
        }
        saveRecentLocations()
    }

    /// 主动探测 NE Tunnel 进程内 Go 代理 (127.0.0.1:8888) 的 TCP 就绪状态。
    /// 127.0.0.1 在 NEProxySettings 例外清单里(见 Tunnel/PacketTunnelProvider.swift),
    /// 本次 connect 不会被代理拦截,直达 Tunnel 进程的 Go HTTP server。
    /// 轮询每 0.3 秒,单次 connect 超时 1 秒(防 socket 挂在 preparing/waiting),
    /// 总超时由参数控制;探到 .ready → completion(true),否则到总超时 → completion(false)。
    private func probeGoProxyReady(timeout: TimeInterval, completion: @escaping (Bool) -> Void) {
        let started = Date()
        let deadline = started.addingTimeInterval(timeout)
        DiagLog.add("[探测] 开始探测 Go 代理 127.0.0.1:8888(总超时 \(Int(timeout)) 秒)")

        var attemptCount = 0
        func attempt() {
            attemptCount += 1
            let myAttempt = attemptCount
            let conn = NWConnection(host: "127.0.0.1", port: 8888, using: .tcp)
            var settled = false

            let retryOrFail: () -> Void = {
                if Date() < deadline {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        attempt()
                    }
                } else {
                    let elapsed = Date().timeIntervalSince(started)
                    DiagLog.add("[探测] 第 \(myAttempt) 次 attempt 后到总超时,Go 就绪探测放弃(总耗时约 \(String(format: "%.2f", elapsed))s)")
                    completion(false)
                }
            }

            conn.stateUpdateHandler = { state in
                guard !settled else { return }
                switch state {
                case .ready:
                    settled = true
                    let elapsed = Date().timeIntervalSince(started)
                    DiagLog.add("[探测] 第 \(myAttempt) 次 attempt TCP .ready,Go 代理可用,总耗时约 \(String(format: "%.2f", elapsed))s")
                    conn.cancel()
                    completion(true)
                case .failed, .cancelled:
                    settled = true
                    conn.cancel()
                    retryOrFail()
                default:
                    break  // .setup / .waiting / .preparing 等中间态忽略,等 ready/failed/单次超时
                }
            }
            conn.start(queue: .main)

            // 单次 connect 1 秒兜底
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                guard !settled else { return }
                settled = true
                DiagLog.add("[探测] 第 \(myAttempt) 次 attempt 单次 1 秒超时,重试")
                conn.cancel()
                retryOrFail()
            }
        }
        attempt()
    }

    /// 主动触发 VPN 连接(冷启动场景)。事件驱动等 .connected,然后给 Go 代理一段就绪缓冲再回调。
    /// 复用 RestartState 持有 observer/finished;object: nil 全接收 + 身份过滤;30 秒超时。
    /// 关键:NE status == .connected 不代表 Go 代理 127.0.0.1:8888 已 ListenAndServe,
    /// 所以 .connected 后再延迟 2 秒,确保用户重启定位服务时代理已经能接请求。
    private func connectVPNForSpoofing(completion: @escaping (Bool, String?) -> Void) {
        DiagLog.add("[冷启动] 进入 connectVPNForSpoofing")
        guard let manager = ContentView.vpnManager else {
            DiagLog.add("[冷启动] 失败:vpnManager 为 nil")
            completion(false, "VPN 配置未初始化,请重启 App")
            return
        }

        let state = RestartState()

        let finish: (Bool, String?) -> Void = { ok, errMsg in
            guard !state.finished else { return }
            state.finished = true
            if let observer = state.observer {
                NotificationCenter.default.removeObserver(observer)
            }
            if ok {
                DiagLog.add("[冷启动] VPN 已连接,启动 Go 代理就绪探测(总超时 10 秒)")
                probeGoProxyReady(timeout: 10) { ready in
                    if ready {
                        DiagLog.add("[冷启动] Go 就绪,回调 completion(true)")
                        completion(true, nil)
                    } else {
                        DiagLog.add("[冷启动] Go 就绪探测超时,回调 completion(false)")
                        completion(false, "Go 代理就绪超时,请重试")
                    }
                }
            } else {
                DiagLog.add("[冷启动] finish 失败:\(errMsg ?? "VPN 启动失败")")
                completion(false, errMsg ?? "VPN 启动失败")
            }
        }

        state.observer = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: .main
        ) { notification in
            guard !state.finished else { return }
            guard let conn = notification.object as? NEVPNConnection,
                  conn === manager.connection else { return }
            DiagLog.add("[冷启动] 观察者收到状态变化: \(manager.connection.status.diagDesc)")
            switch manager.connection.status {
            case .connected:
                finish(true, nil)
            case .invalid:
                finish(false, "VPN 配置失效,请重试")
            default:
                break  // 忽略 .connecting / .disconnecting / .disconnected / .reasserting 中间态
            }
        }

        // 兜底:进来时已是 .connected(罕见,但不接住会被 30 秒超时拖死)
        if manager.connection.status == .connected {
            finish(true, nil)
            return
        }

        do {
            try manager.connection.startVPNTunnel()
            DiagLog.add("[冷启动] 已调 startVPNTunnel,等待 .connected 事件")
        } catch {
            finish(false, "VPN 启动失败:\(error.localizedDescription)")
            return
        }

        // 30 秒超时(与 restartVPNForNewCoordinates 保持一致)
        DispatchQueue.main.asyncAfter(deadline: .now() + 30.0) {
            finish(false, "VPN 连接超时,请重试")
        }
    }

    /// 重连状态持有器:用 class 包住 phase/finished/observer,
    /// 避免 var 被多个 closure 捕获时出现"初始化前捕获"的不稳定写法。
    private final class RestartState {
        var phase = 0
        var finished = false
        var observer: NSObjectProtocol?
    }

    /// VPN 已连状态下切换坐标,需要重启 tunnel 让 NE 重读新坐标。
    /// 用临时独立的 NEVPNStatusDidChange 观察者驱动两阶段状态机:
    /// 阶段0:stopVPNTunnel → 等 .disconnected;阶段1:startVPNTunnel → 等 .connected。
    /// 8 秒超时兜底,RestartState.finished token 防止超时与成功回调冲突。
    /// 整个过程藏在 setAsLocation 已设的 pending 幕布后,成功才弹"重启定位服务"教学。
    private func restartVPNForNewCoordinates() {
        DiagLog.add("[热切] 进入 restartVPNForNewCoordinates")
        guard let manager = ContentView.vpnManager else {
            DiagLog.add("[热切] 失败:vpnManager 为 nil")
            spoofingState = .failed(reason: "VPN 配置未初始化,请重启 App")
            return
        }

        let state = RestartState()

        let finish: (Bool, String?) -> Void = { ok, errMsg in
            guard !state.finished else { return }
            state.finished = true
            if let observer = state.observer {
                NotificationCenter.default.removeObserver(observer)
            }
            if ok {
                DiagLog.add("[热切] VPN 已重连,启动 Go 代理就绪探测(总超时 10 秒)")
                probeGoProxyReady(timeout: 10) { ready in
                    if ready {
                        DiagLog.add("[热切] Go 就绪,0.3 秒后弹定位重启教学")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showRestartLocationGuide = true
                            DiagLog.add("[热切] 已弹出重启定位服务教学")
                        }
                    } else {
                        DiagLog.add("[热切] Go 就绪探测超时,置 failed")
                        spoofingState = .failed(reason: "Go 代理就绪超时,请重试")
                    }
                }
            } else {
                DiagLog.add("[热切] finish 失败:\(errMsg ?? "VPN 重连失败")")
                spoofingState = .failed(reason: errMsg ?? "VPN 重连失败")
            }
        }

        // object: nil 全接收,closure 内部用 === 身份过滤;
        // 避免真机上因 object 过滤导致收不到 NEVPNStatusDidChange 而一直超时。
        state.observer = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: .main
        ) { notification in
            guard !state.finished else { return }
            // 只处理来自当前 manager.connection 的事件
            guard let conn = notification.object as? NEVPNConnection,
                  conn === manager.connection else { return }
            let status = manager.connection.status
            DiagLog.add("[热切] 观察者收到状态变化: \(status.diagDesc) phase=\(state.phase)")
            switch (state.phase, status) {
            case (0, .disconnected), (0, .invalid):
                DiagLog.add("[热切] phase 0→1:tunnel 已停,调 startVPNTunnel 等待 .connected")
                state.phase = 1
                do {
                    try manager.connection.startVPNTunnel()
                } catch {
                    finish(false, "VPN 启动失败:\(error.localizedDescription)")
                }
            case (1, .connected):
                DiagLog.add("[热切] phase 1 收到 .connected,调 finish(true)")
                finish(true, nil)
            default:
                break  // 忽略 .connecting / .disconnecting / .reasserting 中间态
            }
        }

        // 异常兜底:若进来时已是 disconnected(理论上 vpnConnected==true 保证不会),
        // 直接跳阶段 1 启动 tunnel,否则触发 stop 等观察者推进。
        if manager.connection.status == .disconnected || manager.connection.status == .invalid {
            state.phase = 1
            do {
                try manager.connection.startVPNTunnel()
            } catch {
                finish(false, "VPN 启动失败:\(error.localizedDescription)")
            }
        } else {
            DiagLog.add("[热切] 调 stopVPNTunnel,等 .disconnected 事件")
            manager.connection.stopVPNTunnel()
        }

        // 30 秒超时(放宽以适应 GoSpoofer 关闭 drain 与真机 NE 切换的真实耗时)
        DispatchQueue.main.asyncAfter(deadline: .now() + 30.0) {
            finish(false, "VPN 重连超时,请检查网络")
        }
    }

    private func disableSpoofing() {
        let oldName = currentLocationName

        // 进入 pending(关闭中)
        spoofingState = .pending(name: oldName, isClosing: true)

        // 关 VPN
        if let manager = ContentView.vpnManager {
            manager.connection.stopVPNTunnel()
        }
        // 清坐标
        LocationConfiguration.shared.clearCoordinates()
        UserDefaults.standard.removeObject(forKey: "currentLocationName")
        currentLocationName = ""

        // 弹出"请重启定位服务"教学
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            showRestartPhoneGuide = true
        }
    }

    private func loadSavedLocations() {
        if let data = UserDefaults.standard.data(forKey: "savedLocations"),
           let decoded = try? JSONDecoder().decode([SavedLocation].self, from: data) {
            savedLocations = decoded
        }
    }

    private func saveSavedLocations() {
        if let encoded = try? JSONEncoder().encode(savedLocations) {
            UserDefaults.standard.set(encoded, forKey: "savedLocations")
        }
    }

    private func addCurrentSelectionToFavorites() {
        guard let coord = selectedCoordinate,
              let name = selectedLocationName else { return }
        // 避免重复
        if savedLocations.contains(where: { $0.name == name }) {
            // 已存在也给反馈,让用户知道点击生效
            triggerFavoritedFeedback()
            return
        }
        let new = SavedLocation(
            name: name,
            latitude: coord.latitude,
            longitude: coord.longitude
        )
        savedLocations.append(new)
        saveSavedLocations()
        triggerFavoritedFeedback()
    }

    private func triggerFavoritedFeedback() {
        // 触感反馈
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        // 视觉反馈
        justFavorited = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            justFavorited = false
        }
    }

    private func selectFavorite(_ saved: SavedLocation) {
        let coord = CLLocationCoordinate2D(latitude: saved.latitude, longitude: saved.longitude)
        selectedCoordinate = coord
        selectedLocationName = saved.name
        cameraPosition = .region(MKCoordinateRegion(
            center: coord,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        ))
        showFavoritesSheet = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            showLocationSheet = true
        }
    }

    private func deleteFavorite(_ saved: SavedLocation) {
        savedLocations.removeAll { $0.id == saved.id }
        saveSavedLocations()
    }

    private func refreshVPNStatus() {
        if let manager = ContentView.vpnManager {
            vpnStatus = manager.connection.status
            vpnConnected = (vpnStatus == .connected)
        }
    }
}
