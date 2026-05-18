import SwiftUI
import NetworkExtension
import os.log

struct ContentView: View {
    @State private var vpnStatus: NEVPNStatus = .invalid
    @State private var showingInstallationAlert = false
    @State private var installationError: String? = nil

    var body: some View {
        TabView {
            VPNControlView(vpnStatus: $vpnStatus, showingInstallationAlert: $showingInstallationAlert, installationError: $installationError)
                .tabItem {
                    Image(systemName: "network")
                    Text("VPN")
                }
                .tag(0)
            CoordinateInputView()
                .tabItem {
                    Image(systemName: "location.fill")
                    Text("位置")
                }
                .tag(1)
        }
        .onAppear {
            loadVPNConfiguration()
        }
        .alert("VPN 安装", isPresented: $showingInstallationAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(installationError ?? "VPN 配置安装失败")
        }
    }
}

struct SetupStepView: View {
    let stepNumber: Int
    let title: String
    let subtitle: String
    let isCompleted: Bool
    let isCurrent: Bool
    let buttonTitle: String?
    let action: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(isCompleted ? Color.green : (isCurrent ? Color.blue : Color.gray.opacity(0.3)))
                    .frame(width: 32, height: 32)
                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                } else {
                    Text("\(stepNumber)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(isCurrent ? .white : .secondary)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(isCompleted ? .secondary : .primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if let buttonTitle = buttonTitle, isCurrent, let action = action {
                Button(action: action) {
                    Text(buttonTitle)
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                }
            }
        }
        .padding(.vertical, 6)
        .opacity(isCompleted ? 0.7 : 1.0)
    }
}

struct VPNControlView: View {
    @Binding var vpnStatus: NEVPNStatus
    @Binding var showingInstallationAlert: Bool
    @Binding var installationError: String?
    @State private var isConnecting = false
    @State private var needsVPNInstallation = false
    @State private var certInstalled: Bool = UserDefaults.standard.bool(forKey: "certInstalled")
    @State private var certTrusted: Bool = UserDefaults.standard.bool(forKey: "certTrusted")
    @State private var locationSet: Bool = false

    private var isVPNConnected: Bool { vpnStatus == .connected }

    private var allSetupDone: Bool {
        isVPNConnected && certInstalled && certTrusted && locationSet
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // 状态横幅
                    HStack {
                        Image(systemName: allSetupDone ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(allSetupDone ? .green : .orange)
                        Text(allSetupDone ? "定位已生效" : "定位尚未生效")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                    }
                    .padding(12)
                    .background(allSetupDone ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
                    .cornerRadius(10)

                    // VPN 连接卡片
                    VStack(spacing: 12) {
                        HStack {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 12, height: 12)
                            Text("VPN 状态：\(statusText)")
                                .font(.body)
                            Spacer()
                        }

                        if needsVPNInstallation {
                            Button("安装 VPN 配置") {
                                installVPNProfile()
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        } else {
                            Button(action: { toggleVPN() }) {
                                HStack {
                                    if isConnecting {
                                        ProgressView().scaleEffect(0.8)
                                    }
                                    Text(vpnStatus == .connected ? "断开" : "连接")
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(vpnStatus == .connected ? Color.red : Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                            }
                            .disabled(isConnecting)
                        }
                    }
                    .padding(12)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(10)

                    // 设置引导步骤
                    VStack(alignment: .leading, spacing: 4) {
                        Text("设置引导")
                            .font(.headline)
                            .padding(.bottom, 4)

                        SetupStepView(
                            stepNumber: 1, title: "连接 VPN", subtitle: "启用本地 VPN 拦截定位请求",
                            isCompleted: isVPNConnected, isCurrent: !isVPNConnected,
                            buttonTitle: nil, action: nil
                        )

                        SetupStepView(
                            stepNumber: 2, title: "安装证书", subtitle: "在 Safari 中打开 mitm.it 安装证书",
                            isCompleted: certInstalled, isCurrent: isVPNConnected && !certInstalled,
                            buttonTitle: "前往安装", action: {
                                if let url = URL(string: "http://mitm.it") {
                                    UIApplication.shared.open(url)
                                }
                            }
                        )

                        SetupStepView(
                            stepNumber: 3, title: "信任证书", subtitle: "设置 > 通用 > VPN与设备管理",
                            isCompleted: certTrusted, isCurrent: isVPNConnected && certInstalled && !certTrusted,
                            buttonTitle: "前往设置", action: {
                                if let url = URL(string: "App-Prefs:General") {
                                    UIApplication.shared.open(url)
                                }
                            }
                        )

                        SetupStepView(
                            stepNumber: 4, title: "开启证书信任", subtitle: "设置 > 通用 > 关于本机 > 证书信任设置",
                            isCompleted: certTrusted, isCurrent: isVPNConnected && certInstalled && !certTrusted,
                            buttonTitle: "前往设置", action: {
                                if let url = URL(string: "App-Prefs:General") {
                                    UIApplication.shared.open(url)
                                }
                            }
                        )

                        // 步骤3和4合并确认
                        if isVPNConnected && certInstalled && !certTrusted {
                            Button(action: {
                                certTrusted = true
                                UserDefaults.standard.set(true, forKey: "certTrusted")
                            }) {
                                Text("已完成证书信任设置")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(Color.green.opacity(0.1))
                                    .foregroundColor(.green)
                                    .cornerRadius(8)
                            }
                            .padding(.vertical, 4)
                        }

                        // 步骤2确认
                        if isVPNConnected && !certInstalled {
                            Button(action: {
                                certInstalled = true
                                UserDefaults.standard.set(true, forKey: "certInstalled")
                            }) {
                                Text("已完成证书安装")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(Color.green.opacity(0.1))
                                    .foregroundColor(.green)
                                    .cornerRadius(8)
                            }
                            .padding(.vertical, 4)
                        }

                        SetupStepView(
                            stepNumber: 5, title: "选择目标位置", subtitle: "在「位置」标签页搜索或点选",
                            isCompleted: locationSet, isCurrent: isVPNConnected && certInstalled && certTrusted && !locationSet,
                            buttonTitle: nil, action: nil
                        )

                        SetupStepView(
                            stepNumber: 6, title: "重启 VPN", subtitle: "断开再重连使新定位生效",
                            isCompleted: false, isCurrent: isVPNConnected && certInstalled && certTrusted && locationSet,
                            buttonTitle: "重启 VPN", action: {
                                restartVPN()
                            }
                        )

                        SetupStepView(
                            stepNumber: 7, title: "重启定位服务", subtitle: "关闭定位3秒后重新打开",
                            isCompleted: false, isCurrent: false,
                            buttonTitle: "前往设置", action: {
                                if let url = URL(string: "App-Prefs:Privacy&path=LOCATION") {
                                    UIApplication.shared.open(url)
                                }
                            }
                        )
                    }
                    .padding(12)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(10)
                }
                .padding()
            }
            .navigationTitle("任意门")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                checkLocationSet()
                needsVPNInstallation = (ContentView.vpnManager == nil)
            }
        }
    }

    private var statusColor: Color {
        switch vpnStatus {
        case .connected: return .green
        case .connecting, .disconnecting: return .yellow
        case .disconnected: return .red
        default: return .gray
        }
    }

    private var statusText: String {
        switch vpnStatus {
        case .connected: return "已连接"
        case .connecting: return "连接中"
        case .disconnecting: return "断开中"
        case .disconnected: return "未连接"
        case .invalid: return needsVPNInstallation ? "需要安装" : "未配置"
        @unknown default: return "未知"
        }
    }

    private func checkLocationSet() {
        locationSet = UserDefaults.standard.string(forKey: "currentLocationName") != nil
    }

    private func restartVPN() {
        guard let manager = ContentView.vpnManager else { return }
        manager.connection.stopVPNTunnel()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            do {
                try manager.connection.startVPNTunnel()
            } catch {
                os_log("VPN restart failed: %{public}@", error.localizedDescription)
            }
        }
    }
}

extension ContentView {
    static var vpnManager: NETunnelProviderManager?

    func loadVPNConfiguration() {
        NETunnelProviderManager.loadAllFromPreferences { managers, error in
            if let error = error {
                os_log("Failed to load VPN configurations: %{public}@", error.localizedDescription)
                return
            }
            if let manager = managers?.first {
                ContentView.vpnManager = manager
                DispatchQueue.main.async {
                    self.vpnStatus = manager.connection.status
                }
                NotificationCenter.default.addObserver(forName: .NEVPNStatusDidChange, object: manager.connection, queue: .main) { _ in
                    self.vpnStatus = manager.connection.status
                }
            } else {
                DispatchQueue.main.async {
                    self.vpnStatus = .invalid
                }
            }
        }
    }
}

extension VPNControlView {
    func installVPNProfile() {
        let manager = NETunnelProviderManager()
        manager.localizedDescription = "任意门"
        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = "com.whitemirror.location-spoofer.tunnel"
        proto.serverAddress = "127.0.0.1"
        manager.protocolConfiguration = proto
        manager.isEnabled = true
        manager.saveToPreferences { error in
            if let error = error {
                DispatchQueue.main.async {
                    self.installationError = "VPN 配置安装失败：\(error.localizedDescription)"
                    self.showingInstallationAlert = true
                }
                return
            }
            manager.loadFromPreferences { error in
                if let error = error {
                    os_log("Failed to reload: %{public}@", error.localizedDescription)
                }
                DispatchQueue.main.async {
                    ContentView.vpnManager = manager
                    self.needsVPNInstallation = false
                    self.vpnStatus = manager.connection.status
                    NotificationCenter.default.addObserver(forName: .NEVPNStatusDidChange, object: manager.connection, queue: .main) { _ in
                        self.vpnStatus = manager.connection.status
                    }
                }
            }
        }
    }

    func toggleVPN() {
        guard let manager = ContentView.vpnManager else { return }
        isConnecting = true
        if vpnStatus == .connected {
            manager.connection.stopVPNTunnel()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.isConnecting = false
            }
        } else {
            do {
                try manager.connection.startVPNTunnel()
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    self.isConnecting = false
                }
            } catch {
                os_log("Failed to start VPN: %{public}@", error.localizedDescription)
                isConnecting = false
            }
        }
    }
}

#Preview {
    ContentView()
}
