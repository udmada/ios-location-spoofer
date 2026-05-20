import SwiftUI
import NetworkExtension

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showResetConfirm = false
    @State private var showCopiedToast = false
    @ObservedObject private var diagLog = DiagLog.shared

    var body: some View {
        NavigationView {
            List {
                // 关于
                Section("关于") {
                    HStack {
                        Text("任意门")
                        Spacer()
                        Text("Build \(buildNumber)")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("版本")
                        Spacer()
                        Text(appVersion)
                            .foregroundColor(.secondary)
                    }
                }

                // 诊断信息
                Section("诊断信息(发给客服时使用)") {
                    diagnosticRow(label: "VPN 状态", value: vpnStatusText)
                    diagnosticRow(label: "证书状态", value: certificateStatusText)
                    diagnosticRow(label: "当前虚拟定位", value: currentLocationText)
                    diagnosticRow(label: "当前坐标", value: currentCoordinatesText)
                    diagnosticRow(label: "首次配置", value: setupCompletedText)

                    Button(action: { copyDiagnostic() }) {
                        HStack {
                            Image(systemName: "doc.on.doc")
                            Text(showCopiedToast ? "已复制" : "复制诊断信息(含流程日志)")
                            Spacer()
                        }
                        .foregroundColor(showCopiedToast ? .green : .blue)
                    }
                }

                // 流程日志
                Section(header: HStack {
                    Text("流程日志(最近 \(diagLog.entries.count) 条)")
                    Spacer()
                    Button("清空") { diagLog.clear() }
                        .font(.caption)
                        .foregroundColor(.red)
                        .disabled(diagLog.entries.isEmpty)
                }) {
                    if diagLog.entries.isEmpty {
                        Text("暂无日志。操作一次「设为定位」后回来查看。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(diagLog.entries.reversed()) { entry in
                            Text(entry.formatted)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                // 危险操作
                Section("高级") {
                    Button(role: .destructive, action: { showResetConfirm = true }) {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("重置 App(清除所有配置和收藏)")
                        }
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .alert("确认重置 App?", isPresented: $showResetConfirm) {
                Button("取消", role: .cancel) { }
                Button("重置", role: .destructive) { resetApp() }
            } message: {
                Text("将清除所有配置、收藏、证书状态。\n\n重置后需要重新走一次首次配置流程。")
            }
        }
    }

    // MARK: - 诊断信息收集

    @ViewBuilder
    private func diagnosticRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
                .font(.system(.body, design: .monospaced))
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "未知"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "未知"
    }

    private var vpnStatusText: String {
        guard let manager = ContentView.vpnManager else {
            return "未初始化"
        }
        switch manager.connection.status {
        case .invalid:        return "无效"
        case .disconnected:   return "未连接"
        case .connecting:     return "连接中"
        case .connected:      return "已连接"
        case .reasserting:    return "重新连接中"
        case .disconnecting:  return "断开中"
        @unknown default:     return "未知"
        }
    }

    private var certificateStatusText: String {
        let downloaded = UserDefaults.standard.bool(forKey: "certDownloaded")
        let installed = UserDefaults.standard.bool(forKey: "certInstalled")
        let trusted = UserDefaults.standard.bool(forKey: "certTrusted")
        if trusted { return "已信任" }
        if installed { return "已安装未信任" }
        if downloaded { return "已下载未安装" }
        return "未配置"
    }

    private var currentLocationText: String {
        UserDefaults.standard.string(forKey: "currentLocationName") ?? "无"
    }

    private var currentCoordinatesText: String {
        guard let coords = LocationConfiguration.shared.currentCoordinates else {
            return "无"
        }
        return String(format: "%.6f, %.6f", coords.latitude, coords.longitude)
    }

    private var setupCompletedText: String {
        UserDefaults.standard.bool(forKey: "firstSetupCompleted") ? "已完成" : "未完成"
    }

    private func copyDiagnostic() {
        let logBlock = diagLog.entries.isEmpty
            ? "(无日志)"
            : diagLog.entries.map { $0.formatted }.joined(separator: "\n")

        let info = """
        任意门诊断信息
        ─────────────
        App 版本:\(appVersion)
        Build:\(buildNumber)
        VPN 状态:\(vpnStatusText)
        证书状态:\(certificateStatusText)
        当前虚拟定位:\(currentLocationText)
        当前坐标:\(currentCoordinatesText)
        首次配置:\(setupCompletedText)

        ─── 流程日志 ───
        \(logBlock)
        """
        UIPasteboard.general.string = info
        showCopiedToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            showCopiedToast = false
        }
    }

    // MARK: - 重置 App

    private func resetApp() {
        // 断开 VPN
        ContentView.vpnManager?.connection.stopVPNTunnel()
        // 清坐标
        LocationConfiguration.shared.clearCoordinates()
        // 清所有 UserDefaults key
        let keys = [
            "firstSetupCompleted",
            "certDownloaded", "certInstalled", "certTrusted",
            "currentLocationName", "savedLocations", "recentLocations"
        ]
        for key in keys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        // 清诊断日志
        DiagLog.shared.clear()
        dismiss()
    }
}
