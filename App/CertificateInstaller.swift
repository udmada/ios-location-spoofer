import Foundation
import UIKit

// 强引用持有 UIDocumentInteractionController,防止 ARC 提前释放
private class DocControllerHolder: NSObject, UIDocumentInteractionControllerDelegate {
    static let shared = DocControllerHolder()
    var currentController: UIDocumentInteractionController?
    var completion: ((Bool, String?) -> Void)?

    func documentInteractionController(_ controller: UIDocumentInteractionController, willBeginSendingToApplication application: String?) {
        // 用户选了打开方式
    }

    func documentInteractionController(_ controller: UIDocumentInteractionController, didEndSendingToApplication application: String?) {
        // 已发送给系统处理
        completion?(true, nil)
        currentController = nil
        completion = nil
    }

    func documentInteractionControllerDidDismissOpenInMenu(_ controller: UIDocumentInteractionController) {
        // 菜单被取消(用户没选任何项),只有在还没成功发送时才报失败
        if currentController != nil {
            completion?(false, "用户取消了证书安装")
            currentController = nil
            completion = nil
        }
    }
}

enum CertificateInstaller {

    private static let appGroupID = "group.com.whitemirror.location-spoofer"
    private static let caCertKey = "LOCATIONSPOOFER_CA_Certificate"

    /// 从 App Group 读取 CA 证书 PEM
    static func readCACertificatePEM() -> String? {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return nil }
        return defaults.string(forKey: caCertKey)
    }

    /// 将 PEM 格式证书转换为 DER 格式(去掉头尾标签和换行,base64 解码)
    private static func pemToDER(_ pem: String) -> Data? {
        let lines = pem.components(separatedBy: "\n").filter { line in
            !line.hasPrefix("-----") && !line.isEmpty
        }
        let base64 = lines.joined()
        return Data(base64Encoded: base64)
    }

    /// 生成 .mobileconfig 描述文件内容
    static func generateMobileConfig() -> Data? {
        guard let pem = readCACertificatePEM(),
              let derData = pemToDER(pem) else { return nil }

        let derBase64 = derData.base64EncodedString()
        let payloadUUID = UUID().uuidString
        let profileUUID = UUID().uuidString

        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>PayloadContent</key>
            <array>
                <dict>
                    <key>PayloadCertificateFileName</key>
                    <string>LocationSpooferCA.cer</string>
                    <key>PayloadContent</key>
                    <data>
        \(derBase64)
                    </data>
                    <key>PayloadDescription</key>
                    <string>任意门定位修改所需的根证书</string>
                    <key>PayloadDisplayName</key>
                    <string>Location Spoofer CA</string>
                    <key>PayloadIdentifier</key>
                    <string>com.whitemirror.location-spoofer.cert.\(payloadUUID)</string>
                    <key>PayloadType</key>
                    <string>com.apple.security.root</string>
                    <key>PayloadUUID</key>
                    <string>\(payloadUUID)</string>
                    <key>PayloadVersion</key>
                    <integer>1</integer>
                </dict>
            </array>
            <key>PayloadDescription</key>
            <string>安装后请前往 设置>通用>VPN与设备管理 完成证书信任</string>
            <key>PayloadDisplayName</key>
            <string>任意门证书</string>
            <key>PayloadIdentifier</key>
            <string>com.whitemirror.location-spoofer.profile.\(profileUUID)</string>
            <key>PayloadOrganization</key>
            <string>任意门</string>
            <key>PayloadRemovalDisallowed</key>
            <false/>
            <key>PayloadType</key>
            <string>Configuration</string>
            <key>PayloadUUID</key>
            <string>\(profileUUID)</string>
            <key>PayloadVersion</key>
            <integer>1</integer>
        </dict>
        </plist>
        """
        return plist.data(using: .utf8)
    }

    /// 把 mobileconfig 写到临时目录,用 UIDocumentInteractionController 弹出系统安装界面
    /// 返回 true 表示用户成功唤起并接受了系统安装流程
    static func installCertificate(completion: @escaping (Bool, String?) -> Void) {
        guard let configData = generateMobileConfig() else {
            completion(false, "无法读取证书,请先连接VPN生成证书")
            return
        }

        let tmpDir = NSTemporaryDirectory()
        let filePath = (tmpDir as NSString).appendingPathComponent("LocationSpooferCA.mobileconfig")
        let fileURL = URL(fileURLWithPath: filePath)

        do {
            try configData.write(to: fileURL)
        } catch {
            completion(false, "写入临时文件失败:\(error.localizedDescription)")
            return
        }

        DispatchQueue.main.async {
            // 找到最上层的 view controller
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first,
                  var topVC = window.rootViewController else {
                completion(false, "无法获取当前界面")
                return
            }

            // 钻到最上层(处理 modal、navigation 等情况)
            while let presented = topVC.presentedViewController {
                topVC = presented
            }

            let docController = UIDocumentInteractionController(url: fileURL)
            docController.uti = "com.apple.mobileconfig"
            docController.delegate = DocControllerHolder.shared

            DocControllerHolder.shared.currentController = docController
            DocControllerHolder.shared.completion = completion

            // 在屏幕中央弹出"打开方式"菜单
            let rect = CGRect(x: topVC.view.bounds.midX, y: topVC.view.bounds.midY, width: 0, height: 0)
            let didPresent = docController.presentOpenInMenu(from: rect, in: topVC.view, animated: true)

            if !didPresent {
                DocControllerHolder.shared.currentController = nil
                DocControllerHolder.shared.completion = nil
                completion(false, "系统无可用的打开方式,请使用手动安装")
            }
        }
    }
}
