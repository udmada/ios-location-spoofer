//
//  CoordinateInputView.swift
//  location-spoofer
//
//  View for entering coordinates to spoof location
//

import SwiftUI
import UIKit

struct CoordinateInputView: View {
    @StateObject private var locationConfig = LocationConfiguration.shared
    @State private var latitudeText: String = ""
    @State private var longitudeText: String = ""
    @State private var showingPresetLocations = false
    @State private var saveError: String?
    @State private var showingSaveAlert = false
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("纬度")
                                .font(.headline)

                            TextField("例如：40.7128", text: $latitudeText)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .keyboardType(.decimalPad)
                                .onChange(of: latitudeText) { _, newValue in
                                    validateAndSave()
                                }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("经度")
                                .font(.headline)

                            TextField("例如：-74.0060", text: $longitudeText)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .keyboardType(.decimalPad)
                                .onChange(of: longitudeText) { _, newValue in
                                    validateAndSave()
                                }
                        }
                    }
                } header: {
                    Text("目标坐标")
                } footer: {
                    Text("输入你想伪装到的纬度和经度。有效范围：纬度 -90 到 90，经度 -180 到 180。")
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        if let coords = locationConfig.currentCoordinates {
                            HStack {
                                Text("当前设置：")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(String(format: "%.6f, %.6f", coords.latitude, coords.longitude))
                                    .font(.system(.body, design: .monospaced))
                            }
                            .padding(.vertical, 8)
                            
                            Button("清除坐标") {
                                clearCoordinates()
                            }
                            .foregroundColor(.red)
                        } else {
                            Text("尚未配置坐标")
                                .foregroundColor(.secondary)
                                .italic()
                        }
                    }
                } header: {
                    Text("状态")
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("常用地点")
                            .font(.headline)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 12) {
                            PresetLocationButton(name: "纽约", lat: 40.7128, lon: -74.0060, onTap: { lat, lon in
                                setCoordinates(lat: lat, lon: lon)
                            })

                            PresetLocationButton(name: "伦敦", lat: 51.5074, lon: -0.1278, onTap: { lat, lon in
                                setCoordinates(lat: lat, lon: lon)
                            })

                            PresetLocationButton(name: "东京", lat: 35.6762, lon: 139.6503, onTap: { lat, lon in
                                setCoordinates(lat: lat, lon: lon)
                            })

                            PresetLocationButton(name: "悉尼", lat: -33.8688, lon: 151.2093, onTap: { lat, lon in
                                setCoordinates(lat: lat, lon: lon)
                            })

                            PresetLocationButton(name: "巴黎", lat: 48.8566, lon: 2.3522, onTap: { lat, lon in
                                setCoordinates(lat: lat, lon: lon)
                            })

                            PresetLocationButton(name: "洛杉矶", lat: 34.0522, lon: -118.2437, onTap: { lat, lon in
                                setCoordinates(lat: lat, lon: lon)
                            })
                        }
                    }
                } header: {
                    Text("快捷预设")
                } footer: {
                    Text("点击任意预设即可快速设置对应坐标。更改需重启 VPN 后才会生效。")
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("安装指南")
                            .font(.headline)
                        
                        Text("使用位置伪装的步骤：")
                            .font(.subheadline)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("1. 在 VPN 标签页中启用 VPN")
                            Text("2. 在 Safari 中访问 mitm.it")
                            Text("3. 安装 CA 证书")
                            Text("4. 在 设置 > 通用 > VPN与设备管理 中信任该证书")
                            Text("5. 重启 VPN 连接")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                } header: {
                    Text("设置说明")
                }
            }
            .navigationTitle("位置设置")
            .onAppear {
                loadCurrentCoordinates()
            }
            .alert("保存错误", isPresented: $showingSaveAlert) {
                Button("确定") {}
            } message: {
                Text(saveError ?? "保存坐标失败")
            }
        }
    }
    
    private func loadCurrentCoordinates() {
        if let coords = locationConfig.currentCoordinates {
            latitudeText = String(format: "%.6f", coords.latitude)
            longitudeText = String(format: "%.6f", coords.longitude)
        }
    }
    
    private func setCoordinates(lat: Double, lon: Double) {
        latitudeText = String(format: "%.6f", lat)
        longitudeText = String(format: "%.6f", lon)
        validateAndSave()
    }
    
    private func clearCoordinates() {
        latitudeText = ""
        longitudeText = ""
        locationConfig.clearCoordinates()
    }
    
    private func validateAndSave() {
        guard let lat = Double(latitudeText), let lon = Double(longitudeText) else {
            if !latitudeText.isEmpty || !longitudeText.isEmpty {
                saveError = "请输入有效的坐标"
                showingSaveAlert = true
            }
            return
        }
        
        guard lat >= -90 && lat <= 90 else {
            saveError = "纬度必须在 -90 到 90 之间"
            showingSaveAlert = true
            return
        }
        
        guard lon >= -180 && lon <= 180 else {
            saveError = "经度必须在 -180 到 180 之间"
            showingSaveAlert = true
            return
        }
        
        locationConfig.setCoordinates(latitude: lat, longitude: lon)
    }
}

struct PresetLocationButton: View {
    let name: String
    let lat: Double
    let lon: Double
    let onTap: (Double, Double) -> Void
    
    var body: some View {
        Button {
            onTap(lat, lon)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "mappin.circle.fill")
                    .font(.title2)
                Text(name)
                    .font(.caption)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    CoordinateInputView()
}