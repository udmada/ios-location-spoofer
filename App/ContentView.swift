import SwiftUI
import NetworkExtension
import os.log

struct ContentView: View {
    @State private var showingInstallationAlert = false
    @State private var installationError: String?
    @State private var firstSetupCompleted: Bool = UserDefaults.standard.bool(forKey: "firstSetupCompleted")

    var body: some View {
        Group {
            if firstSetupCompleted {
                MapHomeView()
            } else {
                FirstSetupView()
            }
        }
        .onAppear {
            installVPNIfNeeded()
            // 监听 firstSetupCompleted 变化(FirstSetupView 完成 setup 后会写 UserDefaults)
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
                }
            }
        }
    }
}

extension ContentView {
    static var vpnManager: NETunnelProviderManager?
}

#Preview {
    ContentView()
}
