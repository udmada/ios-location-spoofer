import Foundation
import UIKit

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

    /// 把 mobileconfig 写到临时目录,然后调用系统安装
    /// 返回 true 表示成功唤起系统安装界面
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
            if UIApplication.shared.canOpenURL(fileURL) {
                UIApplication.shared.open(fileURL, options: [:]) { success in
                    completion(success, success ? nil : "无法打开系统安装界面")
                }
            } else {
                completion(false, "系统不支持打开此类型文件")
            }
        }
    }
}
