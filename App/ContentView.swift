import SwiftUI
import NetworkExtension
import os.log

struct ContentView: View {
    @State private var vpnStatus: NEVPNStatus = .invalid
    @State private var showingInstallationAlert = false
    @State private var installationError: String?
    @State private var firstSetupCompleted: Bool = UserDefaults.standard.bool(forKey: "firstSetupCompleted")

    var body: some View {
        Group {
            if firstSetupCompleted {
                MapHomeView()
            } else {
                NavigationView {
                    VStack(spacing: 0) {
                        // === 临时调试入口,验证完删除 ===
                        Button(action: {
                            UserDefaults.standard.set(true, forKey: "firstSetupCompleted")
                            firstSetupCompleted = true
                        }) {
                            Text("[DEV] 跳到地图主界面")
                                .font(.caption)
                                .padding(8)
                                .frame(maxWidth: .infinity)
                                .background(Color.red.opacity(0.2))
                                .foregroundColor(.red)
                        }
                        // === 调试入口结束 ===

                        VPNControlView(
                            vpnStatus: $vpnStatus,
                            showingInstallationAlert: $showingInstallationAlert,
                            installationError: $installationError
                        )
                    }
                }
            }
        }
        .onAppear {
            installVPNIfNeeded()
            NotificationCenter.default.addObserver(forName: .NEVPNStatusDidChange, object: nil, queue: .main) { _ in
                if let manager = ContentView.vpnManager {
                    vpnStatus = manager.connection.status
                }
            }
            // 监听 firstSetupCompleted 变化(VPNControlView 完成 setup 后会写 UserDefaults)
            NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
                let newValue = UserDefaults.standard.bool(forKey: "firstSetupCompleted")
                if newValue != firstSetupCompleted {
                    firstSetupCompleted = newValue
                }
            }
        }
        .alert("VPN 安装", isPresented: $showingInstallationAlert) {
            Button("确定") { }
        } message: {
            Text(installationError ?? "")
        }
    }

    private func installVPNIfNeeded() {
        NETunnelProviderManager.loadAllFromPreferences { managers, error in
            if let error = error {
                installationError = "加载 VPN 配置失败:\(error.localizedDescription)"
                showingInstallationAlert = true
                return
            }

            let manager: NETunnelProviderManager
            if let existing = managers?.first {
                manager = existing
            } else {
                manager = NETunnelProviderManager()
            }

            let proto = NETunnelProviderProtocol()
            proto.providerBundleIdentifier = "com.whitemirror.location-spoofer.tunnel"
            proto.serverAddress = "127.0.0.1"
            manager.protocolConfiguration = proto
            manager.localizedDescription = "任意门"
            manager.isEnabled = true

            manager.saveToPreferences { error in
                if let error = error {
                    installationError = "保存 VPN 配置失败:\(error.localizedDescription)"
                    showingInstallationAlert = true
                } else {
                    ContentView.vpnManager = manager
                    DispatchQueue.main.async {
                        vpnStatus = manager.connection.status
                    }
                }
            }
        }
    }
}

struct SetupStepView: View {
    let stepNumber: Int
    let title: String
    let subtitle: String
    let isCompleted: Bool
    let isCurrent: Bool

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
        }
        .padding(.vertical, 6)
        .opacity(isCompleted ? 0.7 : 1.0)
    }
}

struct StepActionButtons: View {
    let showConfirm: Bool
    let confirmTitle: String
    let retryTitle: String
    let onConfirm: () -> Void
    let onAction: () -> Void

    var body: some View {
        if showConfirm {
            HStack(spacing: 8) {
                Button(action: onConfirm) {
                    Text(confirmTitle)
                        .font(.caption).fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.green.opacity(0.1))
                        .foregroundColor(.green)
                        .cornerRadius(8)
                }
                Button(action: onAction) {
                    Text(retryTitle)
                        .font(.caption).fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(8)
                }
            }
            .padding(.vertical, 4)
        } else {
            Button(action: onAction) {
                Text(retryTitle)
                    .font(.caption).fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .cornerRadius(8)
            }
            .padding(.vertical, 4)
        }
    }
}

struct VPNControlView: View {
    @Binding var vpnStatus: NEVPNStatus
    @Binding var showingInstallationAlert: Bool
    @Binding var installationError: String?
    @State private var isConnecting = false
    @State private var needsVPNInstallation = false

    @State private var showStep2Confirm = false
    @State private var certDownloaded: Bool = UserDefaults.standard.bool(forKey: "certDownloaded")
    @State private var showCertInstallError = false
    @State private var certInstallErrorMessage = ""

    @State private var showStep3Confirm = false
    @State private var certInstalled: Bool = UserDefaults.standard.bool(forKey: "certInstalled")

    @State private var showStep4Confirm = false
    @State private var certTrusted: Bool = UserDefaults.standard.bool(forKey: "certTrusted")

    @State private var locationSet: Bool = false

    @State private var vpnRestarted = false
    @State private var vpnRestarting = false

    @State private var showStep7Confirm = false
    @State private var locationServiceRestarted = false

    @State private var showEffectiveAlert = false
    @State private var showRestartLocationPrompt = false
    @State private var isRestoredLocation = false
    @State private var isRestoringLocation = false

    @State private var showStep3Tutorial = false
    @State private var showStep4Tutorial = false
    @State private var showStep7Tutorial = false

    @State private var firstSetupCompleted: Bool = UserDefaults.standard.bool(forKey: "firstSetupCompleted")

    private var isVPNConnected: Bool { vpnStatus == .connected }

    private var allSetupDone: Bool {
        if firstSetupCompleted {
            return isVPNConnected && locationSet && vpnRestarted && locationServiceRestarted
        } else {
            return isVPNConnected && certDownloaded && certInstalled && certTrusted && locationSet && vpnRestarted && locationServiceRestarted
        }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // 状态横幅
                    HStack {
                        Image(systemName: allSetupDone ? "checkmark.circle.fill" : (isRestoredLocation ? "arrow.uturn.backward.circle.fill" : "exclamationmark.triangle.fill"))
                            .foregroundColor(allSetupDone ? .green : (isRestoredLocation ? .blue : .orange))
                        Text(allSetupDone ? "定位已生效" : (isRestoredLocation ? "已恢复真实定位" : "定位尚未生效"))
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                    }
                    .padding(12)
                    .background(allSetupDone ? Color.green.opacity(0.1) : (isRestoredLocation ? Color.blue.opacity(0.1) : Color.orange.opacity(0.1)))
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

                    // 恢复真实定位
                    if UserDefaults.standard.string(forKey: "currentLocationName") != nil && !isVPNConnected && !vpnRestarting {
                        Button(action: { restoreRealLocation() }) {
                            HStack {
                                Image(systemName: isRestoredLocation ? "checkmark.circle.fill" : "arrow.uturn.backward")
                                Text(isRestoredLocation ? "已恢复真实定位" : "恢复真实定位")
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(isRestoredLocation ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                            .foregroundColor(isRestoredLocation ? .green : .red)
                            .cornerRadius(10)
                        }
                        .disabled(isRestoredLocation)
                    }

                    // 设置引导步骤
                    if !firstSetupCompleted {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("设置引导")
                            .font(.headline)
                            .padding(.bottom, 4)

                        Group {
                            // 步骤1
                            SetupStepView(
                                stepNumber: 1, title: "连接 VPN", subtitle: "启用本地 VPN 拦截定位请求",
                                isCompleted: isVPNConnected, isCurrent: !isVPNConnected
                            )
                        }

                        Group {
                            // 步骤2
                            SetupStepView(
                                stepNumber: 2, title: "安装证书", subtitle: "点击按钮跳转 Safari,出现「是否安装」提示后点安装",
                                isCompleted: certDownloaded, isCurrent: isVPNConnected && !certDownloaded
                            )
                            if isVPNConnected && !certDownloaded {
                                VStack(spacing: 12) {
                                    // 主操作:一键安装证书
                                    Button(action: {
                                        CertificateInstaller.installCertificate { success, errorMsg in
                                            if success {
                                                certDownloaded = true
                                                UserDefaults.standard.set(true, forKey: "certDownloaded")
                                            } else {
                                                certInstallErrorMessage = errorMsg ?? "未知错误"
                                                showCertInstallError = true
                                            }
                                        }
                                    }) {
                                        HStack {
                                            Image(systemName: "lock.shield.fill")
                                            Text("一键安装证书")
                                                .fontWeight(.semibold)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(Color.blue)
                                        .foregroundColor(.white)
                                        .cornerRadius(10)
                                    }

                                    // Fallback:手动下载方式(折叠展示)
                                    DisclosureGroup("手动安装(备用方式)") {
                                        VStack(alignment: .leading, spacing: 8) {
                                            HStack {
                                                Text("http://mitm.it")
                                                    .font(.caption)
                                                    .foregroundColor(.blue)
                                                Spacer()
                                                Button(action: {
                                                    UIPasteboard.general.string = "http://mitm.it"
                                                }) {
                                                    HStack(spacing: 4) {
                                                        Image(systemName: "doc.on.doc")
                                                        Text("复制")
                                                    }
                                                    .font(.caption)
                                                    .foregroundColor(.blue)
                                                }
                                            }
                                            .padding(8)
                                            .background(Color(UIColor.tertiarySystemBackground))
                                            .cornerRadius(6)

                                            StepActionButtons(
                                                showConfirm: showStep2Confirm,
                                                confirmTitle: "我已完成",
                                                retryTitle: showStep2Confirm ? "再次下载" : "前往下载",
                                                onConfirm: {
                                                    certDownloaded = true
                                                    UserDefaults.standard.set(true, forKey: "certDownloaded")
                                                },
                                                onAction: {
                                                    if let url = URL(string: "http://mitm.it") {
                                                        UIApplication.shared.open(url)
                                                    }
                                                    showStep2Confirm = true
                                                }
                                            )
                                        }
                                        .padding(.top, 4)
                                    }
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                }
                            }
                        }

                        Group {
                            // 步骤3
                            SetupStepView(
                                stepNumber: 3, title: "安装证书", subtitle: "设置>通用>VPN与设备管理>点击Location Spoofer CA>安装",
                                isCompleted: certInstalled, isCurrent: isVPNConnected && certDownloaded && !certInstalled
                            )
                            if isVPNConnected && certDownloaded && !certInstalled {
                                StepActionButtons(
                                    showConfirm: showStep3Confirm,
                                    confirmTitle: "我已完成",
                                    retryTitle: showStep3Confirm ? "再次前往" : "前往设置",
                                    onConfirm: {
                                        certInstalled = true
                                        UserDefaults.standard.set(true, forKey: "certInstalled")
                                    },
                                    onAction: {
                                        showStep3Tutorial = true
                                        showStep3Confirm = true
                                    }
                                )
                            }
                        }

                        Group {
                            // 步骤4
                            SetupStepView(
                                stepNumber: 4, title: "开启证书信任", subtitle: "设置>通用>关于本机>证书信任设置>开启Location Spoofer CA",
                                isCompleted: certTrusted, isCurrent: isVPNConnected && certDownloaded && certInstalled && !certTrusted
                            )
                            if isVPNConnected && certDownloaded && certInstalled && !certTrusted {
                                StepActionButtons(
                                    showConfirm: showStep4Confirm,
                                    confirmTitle: "我已完成",
                                    retryTitle: showStep4Confirm ? "再次前往" : "前往设置",
                                    onConfirm: {
                                        certTrusted = true
                                        UserDefaults.standard.set(true, forKey: "certTrusted")
                                    },
                                    onAction: {
                                        showStep4Tutorial = true
                                        showStep4Confirm = true
                                    }
                                )
                            }
                        }

                        Group {
                            // 步骤5
                            SetupStepView(
                                stepNumber: 5, title: "选择目标位置", subtitle: "在「位置」标签页搜索或点选",
                                isCompleted: locationSet, isCurrent: isVPNConnected && certDownloaded && certInstalled && certTrusted && !locationSet
                            )
                        }

                        Group {
                            // 步骤6
                            SetupStepView(
                                stepNumber: 6, title: "重启 VPN", subtitle: "断开再重连使新定位生效",
                                isCompleted: vpnRestarted, isCurrent: isVPNConnected && certDownloaded && certInstalled && certTrusted && locationSet && !vpnRestarted
                            )
                            if isVPNConnected && certDownloaded && certInstalled && certTrusted && locationSet && !vpnRestarted {
                                Button(action: {
                                    restartVPN()
                                    vpnRestarted = true
                                }) {
                                    Text("重启 VPN")
                                        .font(.caption).fontWeight(.medium)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(Color.blue.opacity(0.1))
                                        .foregroundColor(.blue)
                                        .cornerRadius(8)
                                }
                                .padding(.vertical, 4)
                            }
                        }

                        Group {
                            // 步骤7
                            SetupStepView(
                                stepNumber: 7, title: "重启定位服务", subtitle: "关闭定位3秒后重新打开",
                                isCompleted: locationServiceRestarted, isCurrent: vpnRestarted && !locationServiceRestarted
                            )
                            if vpnRestarted && !locationServiceRestarted {
                                StepActionButtons(
                                    showConfirm: showStep7Confirm,
                                    confirmTitle: "我已完成",
                                    retryTitle: showStep7Confirm ? "再次前往" : "前往设置",
                                    onConfirm: {
                                        locationServiceRestarted = true
                                        showEffectiveAlert = true
                                    },
                                    onAction: {
                                        showStep7Tutorial = true
                                        showStep7Confirm = true
                                    }
                                )
                            }
                        }
                    }
                    .padding(12)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(10)
                    } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("更改定位")
                            .font(.headline)
                            .padding(.bottom, 4)

                        SetupStepView(
                            stepNumber: 1, title: "连接 VPN", subtitle: "启用本地 VPN 拦截定位请求",
                            isCompleted: isVPNConnected, isCurrent: !isVPNConnected
                        )

                        SetupStepView(
                            stepNumber: 2, title: "选择新位置", subtitle: "在「位置」标签页搜索或点选",
                            isCompleted: locationSet, isCurrent: isVPNConnected && !locationSet
                        )

                        Group {
                            SetupStepView(
                                stepNumber: 3, title: "重启 VPN", subtitle: "断开再重连使新定位生效",
                                isCompleted: vpnRestarted, isCurrent: isVPNConnected && locationSet && !vpnRestarted
                            )
                            if isVPNConnected && locationSet && !vpnRestarted {
                                Button(action: {
                                    restartVPN()
                                    vpnRestarted = true
                                }) {
                                    Text("重启 VPN")
                                        .font(.caption).fontWeight(.medium)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(Color.blue.opacity(0.1))
                                        .foregroundColor(.blue)
                                        .cornerRadius(8)
                                }
                                .padding(.vertical, 4)
                            }
                        }

                        Group {
                            SetupStepView(
                                stepNumber: 4, title: "重启定位服务", subtitle: "关闭定位3秒后重新打开",
                                isCompleted: locationServiceRestarted, isCurrent: vpnRestarted && !locationServiceRestarted
                            )
                            if vpnRestarted && !locationServiceRestarted {
                                StepActionButtons(
                                    showConfirm: showStep7Confirm,
                                    confirmTitle: "我已完成",
                                    retryTitle: showStep7Confirm ? "查看教程" : "操作指引",
                                    onConfirm: {
                                        locationServiceRestarted = true
                                        showEffectiveAlert = true
                                    },
                                    onAction: {
                                        showStep7Tutorial = true
                                        showStep7Confirm = true
                                    }
                                )
                            }
                        }
                    }
                    .padding(12)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(10)
                    }
                }
                .padding()
            }
            .navigationTitle("任意门")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                checkLocationSet()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    needsVPNInstallation = (ContentView.vpnManager == nil)
                }
            }
            .alert("定位已生效", isPresented: $showEffectiveAlert) {
                Button("确定") {
                    firstSetupCompleted = true
                    UserDefaults.standard.set(true, forKey: "firstSetupCompleted")
                }
            } message: {
                Text("新定位已生效，请打开地图验证。")
            }
            .alert("证书安装失败", isPresented: $showCertInstallError) {
                Button("确定") { }
            } message: {
                Text(certInstallErrorMessage + "\n\n请使用「手动安装」展开备用方式。")
            }
            .alert("请重启定位服务", isPresented: $showRestartLocationPrompt) {
                Button("查看教程") {
                    showStep7Tutorial = true
                }
                Button("已完成重启") {
                    isRestoredLocation = true
                    isRestoringLocation = false
                }
                Button("取消", role: .cancel) {
                    isRestoringLocation = false
                }
            } message: {
                Text("请前往 设置>隐私与安全性>定位服务，关闭等待3秒后重新打开。")
            }
            .sheet(isPresented: $showStep3Tutorial) {
                VStack(spacing: 20) {
                    Text("安装证书教程")
                        .font(.title2).fontWeight(.bold)
                    VStack(alignment: .leading, spacing: 16) {
                        Text("① 打开 iPhone「设置」")
                            .font(.title3)
                        Text("② 点击「通用」")
                            .font(.title3)
                        Text("③ 点击「VPN与设备管理」")
                            .font(.title3)
                        Text("④ 找到「Location Spoofer CA」点击进入")
                            .font(.title3)
                        Text("⑤ 点击右上角「安装」")
                            .font(.title3)
                        Text("⑥ 输入手机密码确认安装")
                            .font(.title3)
                    }
                    .padding()
                    Spacer()
                    Button("我知道了") { showStep3Tutorial = false }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .padding(24)
            }
            .sheet(isPresented: $showStep4Tutorial) {
                VStack(spacing: 20) {
                    Text("开启证书信任教程")
                        .font(.title2).fontWeight(.bold)
                    VStack(alignment: .leading, spacing: 16) {
                        Text("① 打开 iPhone「设置」")
                            .font(.title3)
                        Text("② 点击「通用」")
                            .font(.title3)
                        Text("③ 点击「关于本机」")
                            .font(.title3)
                        Text("④ 滑到最底部，点击「证书信任设置」")
                            .font(.title3)
                        Text("⑤ 找到「Location Spoofer CA」")
                            .font(.title3)
                        Text("⑥ 打开右侧开关（变绿色）")
                            .font(.title3)
                        Text("⑦ 弹窗点击「继续」确认")
                            .font(.title3)
                    }
                    .padding()
                    Spacer()
                    Button("我知道了") { showStep4Tutorial = false }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .padding(24)
            }
            .sheet(isPresented: $showStep7Tutorial, onDismiss: {
                if isRestoringLocation && !locationServiceRestarted && !isRestoredLocation {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showRestartLocationPrompt = true
                    }
                }
            }) {
                VStack(spacing: 20) {
                    Text("重启定位服务教程")
                        .font(.title2).fontWeight(.bold)
                    VStack(alignment: .leading, spacing: 16) {
                        Text("① 打开 iPhone「设置」")
                            .font(.title3)
                        Text("② 点击「隐私与安全性」")
                            .font(.title3)
                        Text("③ 点击「定位服务」")
                            .font(.title3)
                        Text("④ 关闭「定位服务」开关")
                            .font(.title3)
                        Text("⑤ 等待 3 秒")
                            .font(.title3).foregroundColor(.red)
                        Text("⑥ 重新打开「定位服务」开关")
                            .font(.title3)
                    }
                    .padding()
                    Spacer()
                    Button("我知道了") { showStep7Tutorial = false }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .padding(24)
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
        vpnRestarting = true
        manager.connection.stopVPNTunnel()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            do {
                try manager.connection.startVPNTunnel()
            } catch {
                os_log("VPN restart failed: %{public}@", error.localizedDescription)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.vpnRestarting = false
            }
        }
    }

    private func restoreRealLocation() {
        isRestoringLocation = true
        LocationConfiguration.shared.clearCoordinates()
        UserDefaults.standard.removeObject(forKey: "currentLocationName")
        locationSet = false
        vpnRestarted = false
        locationServiceRestarted = false
        showStep7Confirm = false
        showRestartLocationPrompt = true
    }
}

extension ContentView {
    static var vpnManager: NETunnelProviderManager?
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
            vpnRestarted = false
            locationServiceRestarted = false
            showStep7Confirm = false
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
