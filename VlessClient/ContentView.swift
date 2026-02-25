import SwiftUI
import Combine
import AppKit

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var mainWindow: NSWindow?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 窗口会由 WindowGroup 自动创建
    }
    
    func showMainWindow() {
        // 查找或创建主窗口
        if let window = mainWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        // 查找现有窗口
        for window in NSApp.windows {
            let className = NSStringFromClass(type(of: window))
            if !className.contains("StatusBar") && !className.contains("Panel") {
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
                NSApp.activate(ignoringOtherApps: true)
                mainWindow = window
                
                // 监听窗口关闭事件,但不销毁窗口,只是隐藏
                NotificationCenter.default.addObserver(
                    forName: NSWindow.willCloseNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    // 不让窗口真正关闭,只是隐藏
                    window.orderOut(nil)
                }
                return
            }
        }
    }
}

// MARK: - App Entry

@main
struct VlessClientApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var configManager  = ConfigManager()
    @StateObject private var logger         = ProxyLogger()
    @StateObject private var proxyViewModel = ProxyViewModel()
    @StateObject private var langManager    = LanguageManager.shared

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(configManager)
                .environmentObject(logger)
                .environmentObject(proxyViewModel)
                .environmentObject(langManager)
                .onAppear {
                    proxyViewModel.setup(configManager: configManager, logger: logger)
                    
                    // 保存窗口引用
                    DispatchQueue.main.async {
                        if let window = NSApp.windows.first(where: {
                            !NSStringFromClass(type(of: $0)).contains("StatusBar")
                        }) {
                            appDelegate.mainWindow = window
                            
                            // ✅ 关键:阻止窗口真正关闭
                            window.delegate = WindowDelegate()
                        }
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 800, height: 600)
        .defaultPosition(.center)

        #if os(macOS)
        MenuBarExtra("VlessClient", systemImage: proxyViewModel.isRunning ? "shield.fill" : "shield") {
            MenuBarView()
                .environmentObject(configManager)
                .environmentObject(logger)
                .environmentObject(proxyViewModel)
                .environmentObject(langManager)
                .environment(\.appDelegate, appDelegate)
        }
        .menuBarExtraStyle(.window)
        #endif
    }
}

// MARK: - Window Delegate (阻止窗口关闭)

class WindowDelegate: NSObject, NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // 不真正关闭窗口,只是隐藏
        sender.orderOut(nil)
        return false
    }
}

// MARK: - Environment Key for AppDelegate

private struct AppDelegateKey: EnvironmentKey {
    static let defaultValue: AppDelegate? = nil
}

extension EnvironmentValues {
    var appDelegate: AppDelegate? {
        get { self[AppDelegateKey.self] }
        set { self[AppDelegateKey.self] = newValue }
    }
}

// MARK: - ProxyViewModel

class ProxyViewModel: ObservableObject {
    @Published var isRunning      = false
    @Published var statusMessage  = ""
    @Published var connectionCount = 0

    private var server: ProxyServer?
    private var configManager: ConfigManager?
    private var logger: ProxyLogger?
    private var cancellables = Set<AnyCancellable>()

    func setup(configManager: ConfigManager, logger: ProxyLogger) {
        self.configManager = configManager
        self.logger = logger
    }

    func toggle() { isRunning ? stop() : start() }

    func start() {
        guard let configManager, let logger,
              let config = configManager.activeConfig else { return }

        server?.stop(); server = nil
        cancellables.removeAll()

        let srv = ProxyServer(config: config, logger: logger)
        server = srv

        srv.$isRunning
            .receive(on: DispatchQueue.main)
            .sink { [weak self] running in
                guard let self else { return }
                self.isRunning = running
                let lm = LanguageManager.shared
                self.statusMessage = running
                    ? lm.t(.statusPort(config.listenPort))
                    : lm.t(.statusStopped)
            }
            .store(in: &cancellables)

        srv.$connectionCount
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.connectionCount = $0 }
            .store(in: &cancellables)

        do {
            try srv.start()
        } catch {
            logger.log(LanguageManager.shared.t(.proxyFailed(error.localizedDescription)))
            DispatchQueue.main.async {
                self.isRunning = false
                self.statusMessage = LanguageManager.shared.t(.proxyFailed(error.localizedDescription))
            }
        }
    }

    func stop() {
        server?.stop(); server = nil
        cancellables.removeAll()
        DispatchQueue.main.async {
            self.isRunning       = false
            self.statusMessage   = LanguageManager.shared.t(.statusStopped)
            self.connectionCount = 0
        }
    }

    func restart() {
        stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.start() }
    }
}

// MARK: - ContentView

struct ContentView: View {
    @EnvironmentObject var configManager: ConfigManager
    @EnvironmentObject var logger: ProxyLogger
    @EnvironmentObject var proxyVM: ProxyViewModel
    @EnvironmentObject var lm: LanguageManager
    @State private var selectedTab = 0

    var body: some View {
        NavigationSplitView {
            SidebarView(selectedTab: $selectedTab)
        } detail: {
            switch selectedTab {
            case 0: DashboardView()
            case 1: ConfigListView()
            case 2: LogView()
            case 3: AboutView()
            default: DashboardView()
            }
        }
        .frame(minWidth: 750, minHeight: 500)
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @Binding var selectedTab: Int
    @EnvironmentObject var proxyVM: ProxyViewModel
    @EnvironmentObject var lm: LanguageManager

    var body: some View {
        List(selection: $selectedTab) {
            Label(lm.t(.navDashboard), systemImage: "gauge").tag(0)
            Label(lm.t(.navConfigs),   systemImage: "list.bullet").tag(1)
            Label(lm.t(.navLogs),      systemImage: "doc.text").tag(2)
            Label(lm.t(.navAbout),     systemImage: "info.circle").tag(3)
        }
        .listStyle(.sidebar)
        .navigationTitle(lm.t(.appName))
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                Divider()
                HStack {
                    Circle()
                        .fill(proxyVM.isRunning ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(proxyVM.isRunning ? lm.t(.statusRunning) : lm.t(.statusStopped))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    // 语言切换按钮
                    Button(action: { lm.toggle() }) {
                        Text("\(lm.language.flag) \(lm.language.displayName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Switch Language / 切换语言")
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
    }
}

// MARK: - Dashboard

struct DashboardView: View {
    @EnvironmentObject var configManager: ConfigManager
    @EnvironmentObject var proxyVM: ProxyViewModel
    @EnvironmentObject var logger: ProxyLogger
    @EnvironmentObject var lm: LanguageManager
    @State private var showImport = false

    var config: VlessConfig? { configManager.activeConfig }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // ── 状态卡片 ──────────────────────────────────────────────
                GroupBox {
                    HStack(spacing: 20) {
                        ZStack {
                            Circle()
                                .fill(proxyVM.isRunning ? Color.green.opacity(0.15) : Color.red.opacity(0.1))
                                .frame(width: 72, height: 72)
                            Image(systemName: proxyVM.isRunning ? "shield.fill" : "shield.slash")
                                .font(.system(size: 32))
                                .foregroundStyle(proxyVM.isRunning ? .green : .red)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(proxyVM.isRunning ? lm.t(.statusActive) : lm.t(.statusStopped))
                                .font(.title2.bold())
                            Text(proxyVM.statusMessage)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if proxyVM.connectionCount > 0 {
                                Text(lm.t(.statusConnections(proxyVM.connectionCount)))
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                            }
                        }

                        Spacer()

                        VStack(spacing: 8) {
                            Button(action: proxyVM.toggle) {
                                Label(proxyVM.isRunning ? lm.t(.btnStop) : lm.t(.btnStart),
                                      systemImage: proxyVM.isRunning ? "stop.fill" : "play.fill")
                                    .frame(width: 100)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(proxyVM.isRunning ? .red : .green)

                            if proxyVM.isRunning {
                                Button(lm.t(.btnRestart), action: proxyVM.restart)
                                    .frame(width: 100)
                            }
                        }
                    }
                    .padding(8)
                } label: {
                    Label(lm.t(.sectionStatus), systemImage: "info.circle")
                }

                // ✅ 新增：应用设置
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(isOn: $configManager.launchAtLogin) {
                            HStack {
                                Image(systemName: "power")
                                    .foregroundStyle(.blue)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(lm.t(.settingsLaunchAtLogin))
                                        .font(.subheadline.bold())
                                    Text(lm.t(.settingsLaunchAtLoginDesc))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .toggleStyle(.switch)
                    }
                    .padding(8)
                } label: {
                    Label(lm.t(.sectionSettings), systemImage: "gearshape")
                }

                // ── 当前配置 ──────────────────────────────────────────────
                if let cfg = config {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            ConfigRow(label: lm.t(.labelServer), value: "\(cfg.server):\(cfg.port)")
                            ConfigRow(label: lm.t(.labelUUID),   value: String(cfg.uuid.prefix(8)) + "...")
                            ConfigRow(label: lm.t(.labelPath),   value: cfg.path)
                            ConfigRow(label: lm.t(.labelSNI),    value: cfg.sni)
                            Divider()
                            HStack {
                                ConfigRow(label: lm.t(.labelSocks5),
                                          value: "socks5://127.0.0.1:\(cfg.listenPort)")
                                Button(action: { copyToClipboard("socks5://127.0.0.1:\(cfg.listenPort)") }) {
                                    Image(systemName: "doc.on.doc")
                                }
                                .buttonStyle(.borderless)
                            }
                            HStack {
                                ConfigRow(label: lm.t(.labelHTTP),
                                          value: "http://127.0.0.1:\(cfg.listenPort)")
                                Button(action: { copyToClipboard("http://127.0.0.1:\(cfg.listenPort)") }) {
                                    Image(systemName: "doc.on.doc")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        .padding(4)
                    } label: {
                        Label("\(lm.t(.sectionActiveConfig)): \(cfg.name)", systemImage: "server.rack")
                    }
                }

                // ── 最近活动 ──────────────────────────────────────────────
                GroupBox {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(logger.logs.prefix(5)) { entry in
                            HStack(alignment: .top, spacing: 8) {
                                Text(entry.timeString)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 60, alignment: .leading)
                                Text(entry.message)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.primary)
                            }
                        }
                        if logger.logs.isEmpty {
                            Text(lm.t(.noActivity))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
                } label: {
                    Label(lm.t(.sectionRecentActivity), systemImage: "clock")
                }
            }
            .padding(20)
        }
        .navigationTitle(lm.t(.navDashboard))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showImport = true }) {
                    Label(lm.t(.btnImportVless), systemImage: "qrcode.viewfinder")
                }
            }
        }
        .sheet(isPresented: $showImport) { ImportView() }
    }

    func copyToClipboard(_ str: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(str, forType: .string)
        #endif
    }
}

// MARK: - ConfigRow

struct ConfigRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label + ":")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)
            Text(value)
                .font(.caption.monospaced())
                .textSelection(.enabled)
        }
    }
}

// MARK: - Config List

struct ConfigListView: View {
    @EnvironmentObject var configManager: ConfigManager
    @EnvironmentObject var proxyVM: ProxyViewModel
    @EnvironmentObject var lm: LanguageManager
    @State private var showAdd    = false
    @State private var editingConfig: VlessConfig?
    @State private var showImport = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(configManager.configs) { config in
                    ConfigRowView(config: config)
                        .contextMenu {
                            Button(lm.t(.ctxSetActive)) {
                                configManager.setActive(config); proxyVM.restart()
                            }
                            Button(lm.t(.ctxEdit))     { editingConfig = config }
                            Button(lm.t(.ctxCopyURI))  { copyURI(config) }
                            Divider()
                            Button(lm.t(.ctxDelete), role: .destructive) {
                                if let idx = configManager.configs.firstIndex(where: { $0.id == config.id }) {
                                    configManager.delete(at: IndexSet([idx]))
                                }
                            }
                        }
                }
            }
            .padding(20)
        }
        .navigationTitle(lm.t(.configListTitle))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showImport = true }) {
                    Label(lm.t(.btnImportURI), systemImage: "link.badge.plus")
                }
            }
            ToolbarItem {
                Button(action: { showAdd = true }) {
                    Label(lm.t(.btnAdd), systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showAdd)          { ConfigEditView(config: nil) }
        .sheet(item: $editingConfig)           { ConfigEditView(config: $0) }
        .sheet(isPresented: $showImport)       { ImportView() }
    }

    func copyURI(_ config: VlessConfig) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(config.toURI(), forType: .string)
        #endif
    }
}

// MARK: - ConfigRowView (✨ 美化后的配置卡片)

struct ConfigRowView: View {
    let config: VlessConfig
    @EnvironmentObject var configManager: ConfigManager
    @EnvironmentObject var proxyVM: ProxyViewModel
    @EnvironmentObject var lm: LanguageManager
    @State private var isHovered = false

    var isActive: Bool { configManager.activeConfig?.id == config.id }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                // 左侧图标
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isActive ? Color.green.opacity(0.15) : Color.blue.opacity(0.1))
                        .frame(width: 56, height: 56)
                    
                    Image(systemName: isActive ? "checkmark.shield.fill" : "server.rack")
                        .font(.system(size: 24))
                        .foregroundStyle(isActive ? .green : .blue)
                }
                
                // 中间配置信息
                VStack(alignment: .leading, spacing: 8) {
                    // 名称 + 标签
                    HStack(spacing: 8) {
                        Text(config.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        
                        if isActive {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 10))
                                Text(lm.t(.badgeActive))
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.green.opacity(0.15))
                            .foregroundStyle(.green)
                            .clipShape(Capsule())
                        }
                    }
                    
                    // 服务器信息
                    HStack(spacing: 16) {
                        // 远程服务器
                        HStack(spacing: 6) {
                            Image(systemName: "globe")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Text("\(config.server):\(config.port)")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        
                        // 分隔符
                        Circle()
                            .fill(Color.secondary.opacity(0.3))
                            .frame(width: 3, height: 3)
                        
                        // 本地端口
                        HStack(spacing: 6) {
                            Image(systemName: "network")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Text(":\(config.listenPort)")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        
                        // 分隔符
                        Circle()
                            .fill(Color.secondary.opacity(0.3))
                            .frame(width: 3, height: 3)
                        
                        // 安全类型
                        HStack(spacing: 4) {
                            Image(systemName: config.security == "tls" ? "lock.fill" : "lock.open")
                                .font(.system(size: 11))
                                .foregroundStyle(config.security == "tls" ? .green : .secondary)
                            Text(config.security.uppercased())
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(config.security == "tls" ? .green : .secondary)
                        }
                    }
                }
                
                Spacer()
                
                // 右侧操作按钮
                if !isActive {
                    Button(action: {
                        configManager.setActive(config)
                        proxyVM.restart()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 14))
                            Text(lm.t(.btnUse))
                                .font(.system(size: 13, weight: .medium))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.blue.opacity(0.1))
                        .foregroundStyle(.blue)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.green)
                        Text(lm.t(.statusActive))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isActive ? Color.green.opacity(0.05) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                isActive ? Color.green.opacity(0.3) :
                                (isHovered ? Color.blue.opacity(0.3) : Color.clear),
                                lineWidth: 1.5
                            )
                    )
            )
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Config Edit View

struct ConfigEditView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var configManager: ConfigManager
    @EnvironmentObject var lm: LanguageManager

    @State private var name:               String
    @State private var server:             String
    @State private var port:               String
    @State private var uuid:               String
    @State private var path:               String
    @State private var sni:                String
    @State private var wsHost:             String
    @State private var listenPort:         String
    @State private var security:           String
    @State private var rejectUnauthorized: Bool

    private let existingConfig: VlessConfig?

    init(config: VlessConfig?) {
        self.existingConfig = config
        let c = config ?? .defaultConfig
        _name               = State(initialValue: c.name)
        _server             = State(initialValue: c.server)
        _port               = State(initialValue: String(c.port))
        _uuid               = State(initialValue: c.uuid)
        _path               = State(initialValue: c.path)
        _sni                = State(initialValue: c.sni)
        _wsHost             = State(initialValue: c.wsHost)
        _listenPort         = State(initialValue: String(c.listenPort))
        _security           = State(initialValue: c.security)
        _rejectUnauthorized = State(initialValue: c.rejectUnauthorized)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(lm.t(.sectionGeneral)) {
                    TextField(lm.t(.fieldName), text: $name)
                }
                Section(lm.t(.sectionServer)) {
                    TextField(lm.t(.fieldServer), text: $server)
                        .onChange(of: server) { _ in
                            if sni == server || sni.isEmpty      { sni    = server }
                            if wsHost == server || wsHost.isEmpty { wsHost = server }
                        }
                    TextField(lm.t(.fieldPort), text: $port)
                }
                Section(lm.t(.sectionAuth)) {
                    TextField(lm.t(.fieldUUID), text: $uuid)
                        .font(.system(.body, design: .monospaced))
                }
                Section(lm.t(.sectionWebSocket)) {
                    TextField(lm.t(.fieldPath),       text: $path)
                    TextField(lm.t(.fieldSNI),        text: $sni)
                    TextField(lm.t(.fieldHostHeader), text: $wsHost)
                    Picker(lm.t(.fieldSecurity), selection: $security) {
                        Text(lm.t(.securityNone)).tag("none")
                        Text(lm.t(.securityTLS)).tag("tls")
                    }
                    .pickerStyle(.segmented)
                }
                Section(lm.t(.sectionLocalProxy)) {
                    TextField(lm.t(.fieldListenPort), text: $listenPort)
                    Toggle(lm.t(.fieldAllowSelfSigned), isOn: $rejectUnauthorized)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(existingConfig == nil ? lm.t(.configEditAdd) : lm.t(.configEditEdit))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(lm.t(.btnCancel)) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(lm.t(.btnSave)) { save() }
                        .disabled(server.isEmpty || uuid.isEmpty)
                }
            }
        }
        .frame(width: 480, height: 520)
    }

    func save() {
        var config = existingConfig ?? VlessConfig(
            name: "", server: "", port: 443, uuid: "", path: "/",
            sni: "", wsHost: "", listenPort: 1088,
            rejectUnauthorized: false, security: "none", encryption: "none"
        )
        config.name               = name.isEmpty ? server : name
        config.server             = server
        config.port               = Int(port) ?? 443
        config.uuid               = uuid
        config.path               = path
        config.sni                = sni
        config.wsHost             = wsHost
        config.listenPort         = Int(listenPort) ?? 1088
        config.security           = security
        config.rejectUnauthorized = rejectUnauthorized

        if existingConfig != nil { configManager.update(config) }
        else                     { configManager.add(config) }
        dismiss()
    }
}

// MARK: - Import View

struct ImportView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var configManager: ConfigManager
    @EnvironmentObject var proxyVM: ProxyViewModel
    @EnvironmentObject var lm: LanguageManager

    @State private var uriText      = ""
    @State private var errorMessage: String?
    @State private var parsedConfig: VlessConfig?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(lm.t(.importDesc))
                    .font(.subheadline).foregroundStyle(.secondary)

                TextEditor(text: $uriText)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 80)
                    .border(Color.secondary.opacity(0.3))
                    .onChange(of: uriText) { _ in parse() }

                if let error = errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red).font(.caption)
                }

                if let cfg = parsedConfig {
                    GroupBox(lm.t(.importParsed)) {
                        VStack(alignment: .leading, spacing: 6) {
                            ConfigRow(label: lm.t(.labelName),   value: cfg.name)
                            ConfigRow(label: lm.t(.labelServer), value: "\(cfg.server):\(cfg.port)")
                            ConfigRow(label: lm.t(.labelUUID),   value: cfg.uuid)
                            ConfigRow(label: lm.t(.labelPath),   value: cfg.path)
                            ConfigRow(label: lm.t(.labelSNI),    value: cfg.sni)
                            ConfigRow(label: lm.t(.fieldSecurity), value: cfg.security)
                        }
                        .padding(4)
                    }
                }

                HStack {
                    Button(action: pasteFromClipboard) {
                        Label(lm.t(.btnPaste), systemImage: "doc.on.clipboard")
                    }
                    Spacer()
                    Button(lm.t(.btnCancel)) { dismiss() }
                    Button(lm.t(.btnImport)) {
                        if let cfg = parsedConfig {
                            configManager.add(cfg)
                            configManager.setActive(cfg)
                            proxyVM.restart()
                            dismiss()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(parsedConfig == nil)
                }

                Spacer()
            }
            .padding(20)
            .navigationTitle(lm.t(.importTitle))
        }
        .frame(width: 500, height: 420)
    }

    func parse() {
        let uri = uriText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !uri.isEmpty else { parsedConfig = nil; errorMessage = nil; return }
        do {
            parsedConfig  = try VlessConfig.parse(from: uri)
            errorMessage  = nil
        } catch {
            parsedConfig  = nil
            errorMessage  = error.localizedDescription
        }
    }

    func pasteFromClipboard() {
        #if os(macOS)
        if let str = NSPasteboard.general.string(forType: .string) { uriText = str }
        #endif
    }
}

// MARK: - Log View

struct LogView: View {
    @EnvironmentObject var logger: ProxyLogger
    @EnvironmentObject var lm: LanguageManager

    var body: some View {
        VStack(spacing: 0) {
            List(logger.logs) { entry in
                HStack(alignment: .top, spacing: 12) {
                    Text(entry.timeString)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(width: 65, alignment: .leading)
                    Text(entry.message)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
                .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
            }
            .listStyle(.plain)

            Divider()
            HStack {
                Text(lm.t(.logEntries(logger.logs.count)))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(lm.t(.btnClear)) { logger.clear() }
                    .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
        }
        .navigationTitle(lm.t(.logTitle))
    }
}

// MARK: - About View

struct AboutView: View {
    @EnvironmentObject var lm: LanguageManager
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // App Logo & Name
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 120, height: 120)
                        
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.system(size: 56))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    
                    VStack(spacing: 4) {
                        Text("VlessClient")
                            .font(.system(size: 32, weight: .bold))
                        Text(lm.t(.aboutVersion))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 32)
                
                // Description
                Text(lm.t(.aboutDesc))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                
                Divider()
                    .padding(.horizontal, 40)
                
                // Developer Info
                GroupBox {
                    VStack(spacing: 10) {
                        AboutInfoRow(
                            icon: "person.circle.fill",
                            iconColor: .blue,
                            title: lm.t(.aboutDeveloper),
                            value: "Oli Liu"
                        )
                        AboutInfoRow(
                            icon: "globe",
                            iconColor: .green,
                            title: lm.t(.aboutWebsite),
                            value: "www.musicses.com",
                            isLink: true,
                            url: "https://www.musicses.com"
                        )
                        AboutInfoRow(
                            icon: "link.circle.fill",
                            iconColor: .orange,
                            title: "GitHub",
                            value: "github.com/liseipi",
                            isLink: true,
                            url: "https://github.com/liseipi"
                        )
                    }
                    .padding(8)
                } label: {
                    Label(lm.t(.aboutContact), systemImage: "person.2.fill")
                        .font(.subheadline)
                }
                .padding(.horizontal, 40)
                
                
                // Features
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        FeatureRow(icon: "checkmark.shield.fill", text: lm.t(.aboutFeature1), color: .green)
                        FeatureRow(icon: "network", text: lm.t(.aboutFeature2), color: .blue)
                        FeatureRow(icon: "arrow.triangle.2.circlepath", text: lm.t(.aboutFeature3), color: .orange)
                        FeatureRow(icon: "menubar.rectangle", text: lm.t(.aboutFeature4), color: .purple)
                        FeatureRow(icon: "globe.badge.chevron.backward", text: lm.t(.aboutFeature5), color: .cyan)
                    }
                    .padding(12)
                } label: {
                    Label(lm.t(.aboutFeatures), systemImage: "star.fill")
                }
                .padding(.horizontal, 40)
                
                // Copyright
                VStack(spacing: 4) {
                    Text("© 2026 liseipi")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(lm.t(.aboutLicense))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle(lm.t(.navAbout))
    }
}

// MARK: - About Info Row

struct AboutInfoRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let value: String
    var isLink: Bool = false
    var url: String?
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(iconColor)
                .frame(width: 28)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                
                if isLink, let url = url {
                    Button(action: {
                        if let nsurl = URL(string: url.hasPrefix("http") ? url : "https://\(url)") {
                            NSWorkspace.shared.open(nsurl)
                        }
                    }) {
                        Text(value)
                            .font(.subheadline)
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        if hovering {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                } else {
                    Text(value)
                        .font(.subheadline)
                        .textSelection(.enabled)
                }
            }
            
            Spacer()
            
            if isLink {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Tech Badge

struct TechBadge: View {
    let icon: String
    let text: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14))
            Text(text)
                .font(.system(size: 13, weight: .medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(color.opacity(0.15))
        .foregroundStyle(color)
        .clipShape(Capsule())
    }
}

// MARK: - Feature Row

struct FeatureRow: View {
    let icon: String
    let text: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(color)
                .frame(width: 24)
            
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
            
            Spacer()
        }
    }
}

// MARK: - Menu Bar View

struct MenuBarView: View {
    @EnvironmentObject var proxyVM: ProxyViewModel
    @EnvironmentObject var configManager: ConfigManager
    @EnvironmentObject var lm: LanguageManager
    @Environment(\.appDelegate) var appDelegate

    var body: some View {
        VStack(spacing: 0) {
            // 顶部信息区（更紧凑）
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: proxyVM.isRunning ? "shield.fill" : "shield.slash")
                        .font(.system(size: 24))
                        .foregroundStyle(proxyVM.isRunning ? .green : .secondary)
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text(lm.t(.appName))
                            .font(.system(size: 15, weight: .medium))
                        Text(proxyVM.isRunning ? lm.t(.statusRunning) : lm.t(.statusStopped))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                
                Divider()
                
                // 配置信息 - 真正左右并排
                if let cfg = configManager.activeConfig {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(cfg.name)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            // 左侧：服务器
                            VStack(alignment: .leading, spacing: 4) {
                                Label {
                                    Text("\(cfg.server):\(cfg.port)")
                                        .font(.system(size: 13, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                } icon: {
                                    Image(systemName: "server.rack")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            
                            // 右侧：本地代理（蓝色突出）
                            VStack(alignment: .leading, spacing: 4) {
                                Label {
                                    Text("127.0.0.1:\(String(cfg.listenPort))")
                                        .font(.system(size: 13, design: .monospaced))
                                        .foregroundStyle(.blue)
                                } icon: {
                                    Image(systemName: "network")
                                        .foregroundStyle(.blue.opacity(0.9))
                                }
                                
                                Text("SOCKS5 / HTTP")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .padding(16)
            
            Divider()
            
            // 操作按钮区
            VStack(spacing: 0) {
                SimpleMenuButton(
                    icon: proxyVM.isRunning ? "stop.circle.fill" : "play.circle.fill",
                    title: proxyVM.isRunning ? lm.t(.menuStopProxy) : lm.t(.menuStartProxy),
                    iconColor: proxyVM.isRunning ? .red : .green
                ) { proxyVM.toggle() }
                
                SimpleMenuButton(icon: "gearshape", title: lm.t(.menuSettings)) {
                    appDelegate?.showMainWindow()
                }
                
                Divider().padding(.horizontal, 16)
                
                SimpleMenuButton(icon: "globe", title: "\(lm.language.flag) \(lm.language.displayName)") {
                    lm.toggle()
                }
                
                Divider().padding(.horizontal, 16)
                
                SimpleMenuButton(
                    icon: "power",
                    title: lm.t(.menuQuit),
                    iconColor: .red,
                    titleColor: .red
                ) {
                    proxyVM.stop()
                    NSApp.terminate(nil)
                }
            }
            .padding(.vertical, 8)
        }
        .frame(width: 260)
    }
}

// MARK: - Simple Menu Button Component

struct SimpleMenuButton: View {
    let icon: String
    let title: String
    var iconColor: Color = .primary
    var titleColor: Color = .primary
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(iconColor)
                    .frame(width: 20, alignment: .center)
                
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(titleColor)
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .background(
                isHovered
                    ? Color(nsColor: .controlBackgroundColor).opacity(0.5)
                    : Color.clear
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
