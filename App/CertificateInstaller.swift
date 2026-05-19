import Foundation
import UIKit

enum CertificateInstaller {

    /// 证书安装的伪域名,由本地 VPN 代理拦截
    private static let certURL = "http://rendoor.cert/"

    /// 唤起 Safari 跳转到证书下载页(由本地 VPN 拦截响应)
    /// 返回 true 表示成功唤起 Safari
    static func installCertificate(completion: @escaping (Bool, String?) -> Void) {
        guard let url = URL(string: certURL) else {
            completion(false, "URL 构造失败")
            return
        }

        DispatchQueue.main.async {
            UIApplication.shared.open(url, options: [:]) { success in
                if success {
                    completion(true, nil)
                } else {
                    completion(false, "无法打开 Safari,请检查 VPN 连接")
                }
            }
        }
    }
}
