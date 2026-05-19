import Foundation

/// 虚拟定位的运行状态
/// 用 enum 收敛三态,SwiftUI 中用 switch 强制穷举,避免状态不一致
enum SpoofingState: Equatable {
    /// 未开启
    case off
    /// 正在生效中(用户已点设定/关闭,但还没完成"重启定位服务")
    case pending(name: String, isClosing: Bool)
    /// 已开启
    case on(name: String)
    /// 操作失败(具体错误原因)
    case failed(reason: String)

    /// 顶部状态卡主文案
    var primaryText: String {
        switch self {
        case .off:
            return "未开启"
        case .pending(_, let isClosing):
            return isClosing ? "正在关闭..." : "正在生效中"
        case .on(let name):
            return "已开启:\(name)"
        case .failed(let reason):
            return "开启失败:\(reason)"
        }
    }

    /// 顶部状态卡副文案(可选)
    var subText: String? {
        switch self {
        case .off, .on, .failed:
            return nil
        case .pending:
            return "请重启定位服务"
        }
    }

    /// 状态卡圆点颜色(用 SwiftUI Color 名)
    var indicatorColorName: String {
        switch self {
        case .off:      return "gray"
        case .pending:  return "yellow"
        case .on:       return "blue"
        case .failed:   return "red"
        }
    }

    /// 主操作按钮文案(nil 表示不显示按钮)
    var actionLabel: String? {
        switch self {
        case .off:      return nil   // off 时主操作藏在底部"设为虚拟定位"
        case .pending:  return nil   // pending 时按钮在重启教学页里
        case .on:       return "关闭"
        case .failed:   return "重试"
        }
    }
}
