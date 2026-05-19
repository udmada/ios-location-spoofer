# 任意门 - iOS 定位修改工具

## 项目概述
基于 acheong08/ios-location-spoofer 的 fork，改造成中文界面的定位修改工具"任意门"。

## 技术栈
- Swift / SwiftUI / iOS 原生
- MapKit + CoreLocation
- Network Extension (VPN)
- XcodeGen (project.yml)
- GitHub Actions 云编译 + TestFlight 分发

## 关键文件
- App/ContentView.swift — 主页（VPN控制 + 7步/4步引导流程）
- App/CoordinateInputView.swift — 位置页（地图选点 + 搜索 + 收藏夹）
- App/CoordinateConverter.swift — GCJ-02/WGS-84 坐标转换
- App/LocationConfiguration.swift — 坐标存储配置
- Resources/Info.plist — App 显示名"任意门"，含 ATS 例外
- project.yml — XcodeGen 配置
- .github/workflows/build.yml — CI 构建 + TestFlight 上传

## 编辑规则
- 这是 Swift 项目，优先用 sed 做文本替换，避免 Edit 工具卡住
- 大改动用 Write 工具直接覆盖整个文件
- 所有用户可见文字为中文
- 不要修改 Tunnel/ 和 GoSpoofer/ 目录的代码
- commit 后统一 push，减少构建次数
