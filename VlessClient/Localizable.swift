import Foundation
import SwiftUI
import Combine

// MARK: - Language

enum AppLanguage: String, CaseIterable {
    case english = "en"
    case chinese = "zh"

    var displayName: String {
        switch self {
        case .english: return "English"
        case .chinese: return "中文"
        }
    }

    var flag: String {
        switch self {
        case .english: return "🇺🇸"
        case .chinese: return "🇨🇳"
        }
    }
}

// MARK: - LanguageManager

class LanguageManager: ObservableObject {
    @Published var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "app_language") }
    }

    static let shared = LanguageManager()

    private init() {
        let saved = UserDefaults.standard.string(forKey: "app_language") ?? ""
        self.language = AppLanguage(rawValue: saved) ?? .english
    }

    func toggle() {
        language = (language == .english) ? .chinese : .english
    }

    func t(_ key: L10n) -> String { key.string(language) }
}

// MARK: - L10n Keys

enum L10n {
    // App / Sidebar
    case appName
    case navDashboard
    case navConfigs
    case navLogs
    case navAbout

    // Status
    case statusRunning
    case statusStopped
    case statusActive
    case statusPort(Int)
    case statusConnections(Int)

    // Dashboard
    case btnStart
    case btnStop
    case btnRestart
    case btnImportVless
    case sectionStatus
    case sectionActiveConfig
    case sectionRecentActivity
    case noActivity
    case labelServer
    case labelUUID
    case labelPath
    case labelSNI
    case labelSocks5
    case labelHTTP

    // Settings
    case sectionSettings
    case settingsLaunchAtLogin
    case settingsLaunchAtLoginDesc

    // Config List
    case configListTitle
    case btnImportURI
    case btnAdd
    case badgeActive
    case btnUse
    case ctxSetActive
    case ctxEdit
    case ctxCopyURI
    case ctxDelete

    // Config Edit
    case configEditAdd
    case configEditEdit
    case sectionGeneral
    case sectionServer
    case sectionAuth
    case sectionWebSocket
    case sectionLocalProxy
    case fieldName
    case fieldServer
    case fieldPort
    case fieldUUID
    case fieldPath
    case fieldSNI
    case fieldHostHeader
    case fieldSecurity
    case securityNone
    case securityTLS
    case fieldListenPort
    case fieldAllowSelfSigned
    case btnCancel
    case btnSave

    // Import
    case importTitle
    case importDesc
    case importParsed
    case importError
    case btnPaste
    case btnImport
    case labelName

    // Logs
    case logTitle
    case logEntries(Int)
    case btnClear

    // About
    case aboutVersion
    case aboutDesc
    case aboutDeveloper
    case aboutWebsite
    case aboutContact
    case aboutTechStack
    case aboutFeatures
    case aboutFeature1
    case aboutFeature2
    case aboutFeature3
    case aboutFeature4
    case aboutFeature5
    case aboutLicense

    // MenuBar
    case menuStartProxy
    case menuStopProxy
    case menuSettings
    case menuQuit

    // Proxy Logger messages
    case proxyStarted(String)
    case proxyStopped
    case proxyFailed(String)

    // MARK: - Strings

    func string(_ lang: AppLanguage) -> String {
        switch lang {
        case .english: return en
        case .chinese: return zh
        }
    }

    private var en: String {
        switch self {
        case .appName:                  return "VlessClient"
        case .navDashboard:             return "Dashboard"
        case .navConfigs:               return "Configs"
        case .navLogs:                  return "Logs"
        case .navAbout:                 return "About"

        case .statusRunning:            return "Running"
        case .statusStopped:            return "Stopped"
        case .statusActive:             return "Proxy Active"
        case .statusPort(let p):        return "Listening on port \(p)"
        case .statusConnections(let n): return "\(n) connection\(n == 1 ? "" : "s")"

        case .btnStart:                 return "Start"
        case .btnStop:                  return "Stop"
        case .btnRestart:               return "Restart"
        case .btnImportVless:           return "Import VLESS"
        case .sectionStatus:            return "Status"
        case .sectionActiveConfig:      return "Active Config"
        case .sectionRecentActivity:    return "Recent Activity"
        case .noActivity:               return "No activity yet"
        case .labelServer:              return "Server"
        case .labelUUID:                return "UUID"
        case .labelPath:                return "Path"
        case .labelSNI:                 return "SNI"
        case .labelSocks5:              return "SOCKS5"
        case .labelHTTP:                return "HTTP"

        case .sectionSettings:          return "Settings"
        case .settingsLaunchAtLogin:    return "Launch at Login"
        case .settingsLaunchAtLoginDesc: return "Start VlessClient automatically when you log in (won't auto-connect)"

        case .configListTitle:          return "Configurations"
        case .btnImportURI:             return "Import URI"
        case .btnAdd:                   return "Add"
        case .badgeActive:              return "ACTIVE"
        case .btnUse:                   return "Use"
        case .ctxSetActive:             return "Set Active"
        case .ctxEdit:                  return "Edit"
        case .ctxCopyURI:               return "Copy URI"
        case .ctxDelete:                return "Delete"

        case .configEditAdd:            return "Add Config"
        case .configEditEdit:           return "Edit Config"
        case .sectionGeneral:           return "General"
        case .sectionServer:            return "Server"
        case .sectionAuth:              return "Authentication"
        case .sectionWebSocket:         return "WebSocket"
        case .sectionLocalProxy:        return "Local Proxy"
        case .fieldName:                return "Name"
        case .fieldServer:              return "Server"
        case .fieldPort:                return "Port"
        case .fieldUUID:                return "UUID"
        case .fieldPath:                return "Path"
        case .fieldSNI:                 return "SNI"
        case .fieldHostHeader:          return "Host Header"
        case .fieldSecurity:            return "Security"
        case .securityNone:             return "None"
        case .securityTLS:              return "TLS"
        case .fieldListenPort:          return "Listen Port"
        case .fieldAllowSelfSigned:     return "Allow Self-signed Certificate"
        case .btnCancel:                return "Cancel"
        case .btnSave:                  return "Save"

        case .importTitle:              return "Import VLESS URI"
        case .importDesc:               return "Paste a VLESS URI to import a server configuration."
        case .importParsed:             return "Parsed Config"
        case .importError:              return "Invalid URI"
        case .btnPaste:                 return "Paste"
        case .btnImport:                return "Import"
        case .labelName:                return "Name"

        case .logTitle:                 return "Logs"
        case .logEntries(let n):        return "\(n) entr\(n == 1 ? "y" : "ies")"
        case .btnClear:                 return "Clear"

        // About
        case .aboutVersion:             return "Version 1.0"
        case .aboutDesc:                return "A modern VLESS protocol client for macOS with SOCKS5 and HTTP proxy support."
        case .aboutDeveloper:           return "Developer"
        case .aboutWebsite:             return "Website"
        case .aboutContact:             return "Contact Information"
        case .aboutTechStack:           return "Technology Stack"
        case .aboutFeatures:            return "Key Features"
        case .aboutFeature1:            return "VLESS protocol with WebSocket support"
        case .aboutFeature2:            return "SOCKS5 & HTTP proxy in one port"
        case .aboutFeature3:            return "Auto-reconnect on network changes"
        case .aboutFeature4:            return "Menu bar quick access"
        case .aboutFeature5:            return "Multi-language support (EN/中文)"
        case .aboutLicense:             return "Open Source · MIT License"

        case .menuStartProxy:           return "Start Proxy"
        case .menuStopProxy:            return "Stop Proxy"
        case .menuSettings:             return "Settings..."
        case .menuQuit:                 return "Quit"

        case .proxyStarted(let s):      return "✅ Proxy started → \(s)"
        case .proxyStopped:             return "🛑 Proxy stopped"
        case .proxyFailed(let e):       return "❌ Failed to start: \(e)"
        }
    }

    private var zh: String {
        switch self {
        case .appName:                  return "VlessClient"
        case .navDashboard:             return "概览"
        case .navConfigs:               return "配置"
        case .navLogs:                  return "日志"
        case .navAbout:                 return "关于"

        case .statusRunning:            return "运行中"
        case .statusStopped:            return "已停止"
        case .statusActive:             return "代理已启动"
        case .statusPort(let p):        return "监听端口 \(p)"
        case .statusConnections(let n): return "\(n) 个连接"

        case .btnStart:                 return "启动"
        case .btnStop:                  return "停止"
        case .btnRestart:               return "重启"
        case .btnImportVless:           return "导入 VLESS"
        case .sectionStatus:            return "状态"
        case .sectionActiveConfig:      return "当前配置"
        case .sectionRecentActivity:    return "最近活动"
        case .noActivity:               return "暂无活动"
        case .labelServer:              return "服务器"
        case .labelUUID:                return "UUID"
        case .labelPath:                return "路径"
        case .labelSNI:                 return "SNI"
        case .labelSocks5:              return "SOCKS5"
        case .labelHTTP:                return "HTTP"

        case .sectionSettings:          return "设置"
        case .settingsLaunchAtLogin:    return "开机自启动"
        case .settingsLaunchAtLoginDesc: return "登录时自动启动应用（不会自动连接代理）"

        case .configListTitle:          return "配置列表"
        case .btnImportURI:             return "导入链接"
        case .btnAdd:                   return "添加"
        case .badgeActive:              return "使用中"
        case .btnUse:                   return "使用"
        case .ctxSetActive:             return "设为当前"
        case .ctxEdit:                  return "编辑"
        case .ctxCopyURI:               return "复制链接"
        case .ctxDelete:                return "删除"

        case .configEditAdd:            return "添加配置"
        case .configEditEdit:           return "编辑配置"
        case .sectionGeneral:           return "基本信息"
        case .sectionServer:            return "服务器"
        case .sectionAuth:              return "认证"
        case .sectionWebSocket:         return "WebSocket"
        case .sectionLocalProxy:        return "本地代理"
        case .fieldName:                return "名称"
        case .fieldServer:              return "服务器"
        case .fieldPort:                return "端口"
        case .fieldUUID:                return "UUID"
        case .fieldPath:                return "路径"
        case .fieldSNI:                 return "SNI"
        case .fieldHostHeader:          return "Host 头"
        case .fieldSecurity:            return "加密方式"
        case .securityNone:             return "无"
        case .securityTLS:              return "TLS"
        case .fieldListenPort:          return "监听端口"
        case .fieldAllowSelfSigned:     return "允许自签名证书"
        case .btnCancel:                return "取消"
        case .btnSave:                  return "保存"

        case .importTitle:              return "导入 VLESS 链接"
        case .importDesc:               return "粘贴 VLESS 链接以导入服务器配置。"
        case .importParsed:             return "解析结果"
        case .importError:              return "链接格式错误"
        case .btnPaste:                 return "粘贴"
        case .btnImport:                return "导入"
        case .labelName:                return "名称"

        case .logTitle:                 return "日志"
        case .logEntries(let n):        return "共 \(n) 条"
        case .btnClear:                 return "清空"

        // About
        case .aboutVersion:             return "版本 1.0"
        case .aboutDesc:                return "一个现代化的 macOS VLESS 协议客户端，支持 SOCKS5 和 HTTP 代理。"
        case .aboutDeveloper:           return "开发者"
        case .aboutWebsite:             return "官网"
        case .aboutContact:             return "联系方式"
        case .aboutTechStack:           return "技术栈"
        case .aboutFeatures:            return "主要特性"
        case .aboutFeature1:            return "支持 VLESS 协议与 WebSocket 传输"
        case .aboutFeature2:            return "单端口同时支持 SOCKS5 和 HTTP 代理"
        case .aboutFeature3:            return "网络变化时自动重连"
        case .aboutFeature4:            return "菜单栏快速访问"
        case .aboutFeature5:            return "多语言支持（English/中文）"
        case .aboutLicense:             return "开源项目 · MIT 协议"

        case .menuStartProxy:           return "启动代理"
        case .menuStopProxy:            return "停止代理"
        case .menuSettings:             return "设置..."
        case .menuQuit:                 return "退出"

        case .proxyStarted(let s):      return "✅ 代理已启动 → \(s)"
        case .proxyStopped:             return "🛑 代理已停止"
        case .proxyFailed(let e):       return "❌ 启动失败: \(e)"
        }
    }
}
