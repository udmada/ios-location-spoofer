import SwiftUI
import NetworkExtension

/// 首次配置的 3 个步骤
enum SetupStep: Int, CaseIterable {
    case welcome = 0  // 欢迎页
    case vpn = 1      // 步骤 1:VPN 权限
    case cert = 2     // 步骤 2:证书安装
    case trust = 3    // 步骤 3:证书信任
    case done = 4     // 完成页

    /// 进度条:步骤 1/2/3 时显示进度,welcome 和 done 不显示
    var progressIndex: Int? {
        switch self {
        case .welcome, .done: return nil
        case .vpn: return 1
        case .cert: return 2
        case .trust: return 3
        }
    }

    var title: String {
        switch self {
        case .welcome: return ""
        case .vpn: return "授权 VPN"
        case .cert: return "下载证书"
        case .trust: return "信任证书"
        case .done: return ""
        }
    }
}

struct FirstSetupView: View {
    @State private var currentStep: SetupStep = .welcome
    @State private var errorMessage: String? = nil
    @State private var isProcessing: Bool = false

    /// 配置完成回调,由 ContentView 监听 firstSetupCompleted 变化即可,这里不必显式传

    var body: some View {
        ZStack {
            // 整体淡入效果
            switch currentStep {
            case .welcome:
                welcomeView
                    .transition(.opacity)
            case .vpn, .cert, .trust:
                progressView
                    .transition(.opacity)
            case .done:
                doneView
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: currentStep)
        .alert("出错了", isPresented: .constant(errorMessage != nil), presenting: errorMessage) { _ in
            Button("好的") { errorMessage = nil }
        } message: { msg in
            Text(msg)
        }
    }

    // MARK: - 欢迎页

    private var welcomeView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "location.fill.viewfinder")
                .font(.system(size: 72))
                .foregroundColor(.blue)

            Text("欢迎使用任意门")
                .font(.largeTitle).fontWeight(.bold)

            Text("3 步完成配置,从此一键改定位")
                .font(.title3)
                .foregroundColor(.secondary)

            Spacer()

            Button(action: { currentStep = .vpn }) {
                Text("开始配置")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 32)

            Text("配置过程会请求 VPN 权限和证书安装\n这是实现定位修改的必要步骤")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
        }
    }

    // MARK: - 进度页(共用 vpn / cert / trust 三个步骤)

    private var progressView: some View {
        VStack(spacing: 32) {
            Spacer().frame(height: 40)

            // 进度条:1/3 → 2/3 → 3/3
            progressIndicator

            // 当前步骤标题
            Text(currentStep.title)
                .font(.title).fontWeight(.bold)

            // 步骤说明
            stepInstruction
                .padding(.horizontal, 32)

            Spacer()

            // 操作按钮
            stepActionButton
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
        }
    }

    private var progressIndicator: some View {
        HStack(spacing: 8) {
            ForEach(1...3, id: \.self) { idx in
                Circle()
                    .fill(progressColor(at: idx))
                    .frame(width: 12, height: 12)
                if idx < 3 {
                    Rectangle()
                        .fill(progressColor(at: idx))
                        .frame(width: 40, height: 2)
                }
            }
        }
    }

    private func progressColor(at index: Int) -> Color {
        guard let current = currentStep.progressIndex else { return .gray.opacity(0.3) }
        return index <= current ? .blue : .gray.opacity(0.3)
    }

    @ViewBuilder
    private var stepInstruction: some View {
        switch currentStep {
        case .vpn:
            VStack(spacing: 12) {
                Text("请在系统弹窗中点击「允许」并输入手机密码")
                    .font(.body)
                    .multilineTextAlignment(.center)
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.blue.opacity(0.6))
                    .padding(.top, 20)
            }
        case .cert:
            VStack(spacing: 12) {
                Text("点击下方按钮,Safari 会自动弹出证书安装提示。")
                    .font(.body)
                    .multilineTextAlignment(.center)
                Text("请按系统提示完成证书下载。")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Text("如果 Safari 提示证书已存在,或直接跳转到了「信任设置」界面,说明证书已安装,关闭 Safari 直接进入下一步即可。")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        case .trust:
            VStack(alignment: .leading, spacing: 14) {
                Text("证书下载后,需要手动信任:")
                    .font(.body)
                Text("① 打开 iPhone「设置」")
                Text("② 进入「通用」→「关于本机」")
                Text("③ 滚到底部找到「证书信任设置」")
                Text("④ 打开「Location Spoofer CA」开关")
                Text("⑤ 在弹窗中点「继续」")
                Text("完成后回到本页面")
                    .font(.body)
                    .foregroundColor(.blue)
                    .padding(.top, 8)
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var stepActionButton: some View {
        switch currentStep {
        case .vpn:
            Button(action: { triggerVPNSetup() }) {
                Text(isProcessing ? "正在配置..." : "授权 VPN")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isProcessing ? Color.gray : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .disabled(isProcessing)
        case .cert:
            Button(action: { triggerCertInstall() }) {
                Text(isProcessing ? "正在跳转..." : "安装证书")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isProcessing ? Color.gray : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .disabled(isProcessing)
        case .trust:
            Button(action: { confirmTrust() }) {
                Text("我已完成信任设置")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
        default:
            EmptyView()
        }
    }

    // MARK: - 完成页

    private var doneView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)
            Text("配置完成!")
                .font(.largeTitle).fontWeight(.bold)
            Text("现在可以一键修改你的定位了")
                .font(.title3)
                .foregroundColor(.secondary)
            Spacer()
            Button(action: { completeSetup() }) {
                Text("开始使用")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
    }

    // MARK: - 占位:D2/D3 实现

    private func triggerVPNSetup() {
        isProcessing = true

        if let manager = ContentView.vpnManager {
            startTunnelAndAdvance(manager: manager)
        } else {
            // 首次:vpnManager 还没就绪,当场安装配置再启动
            ContentView.installAndStartVPN { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let manager):
                        startTunnelAndAdvance(manager: manager)
                    case .failure(let error):
                        isProcessing = false
                        errorMessage = "VPN 配置安装失败:\(error.localizedDescription)"
                    }
                }
            }
        }
    }

    /// 启动 VPN tunnel,3 秒后检查连接状态,连上就推进到 .cert,否则报超时。
    private func startTunnelAndAdvance(manager: NETunnelProviderManager) {
        do {
            try manager.connection.startVPNTunnel()
            // 等待 3 秒看是否真的连上
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                isProcessing = false
                if manager.connection.status == .connected {
                    currentStep = .cert
                } else {
                    errorMessage = "VPN 连接超时,请重新尝试或检查网络。"
                }
            }
        } catch {
            isProcessing = false
            errorMessage = "VPN 启动失败:\(error.localizedDescription)"
        }
    }

    private func triggerCertInstall() {
        isProcessing = true

        CertificateInstaller.installCertificate { success, errMsg in
            DispatchQueue.main.async {
                isProcessing = false
                if success {
                    // Safari 已唤起,等用户从 Safari 回来后,自动到 trust 步骤
                    UserDefaults.standard.set(true, forKey: "certDownloaded")
                    currentStep = .trust
                } else {
                    errorMessage = errMsg ?? "证书安装唤起失败"
                }
            }
        }
    }

    private func confirmTrust() {
        // 手动确认信任(iOS 没有完美的"检测证书是否被信任"API)
        UserDefaults.standard.set(true, forKey: "certInstalled")
        UserDefaults.standard.set(true, forKey: "certTrusted")
        currentStep = .done
    }

    private func completeSetup() {
        UserDefaults.standard.set(true, forKey: "firstSetupCompleted")
        UserDefaults.standard.set(true, forKey: "certDownloaded")
        UserDefaults.standard.set(true, forKey: "certInstalled")
        UserDefaults.standard.set(true, forKey: "certTrusted")
    }
}
