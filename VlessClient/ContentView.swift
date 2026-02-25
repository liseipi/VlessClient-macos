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
        List {
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
            .onDelete { configManager.delete(at: $0) }
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

// MARK: - ConfigRowView

struct ConfigRowView: View {
    let config: VlessConfig
    @EnvironmentObject var configManager: ConfigManager
    @EnvironmentObject var proxyVM: ProxyViewModel
    @EnvironmentObject var lm: LanguageManager

    var isActive: Bool { configManager.activeConfig?.id == config.id }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(config.name).font(.headline)
                    if isActive {
                        Text(lm.t(.badgeActive))
                            .font(.caption.bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.green.opacity(0.15))
                            .foregroundStyle(.green)
                            .clipShape(Capsule())
                    }
                }
                Text("\(config.server):\(config.port)  ·  port \(config.listenPort)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !isActive {
                Button(lm.t(.btnUse)) {
                    configManager.setActive(config); proxyVM.restart()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 4)
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

// MARK: - Menu Bar View

struct MenuBarView: View {
    @EnvironmentObject var proxyVM: ProxyViewModel
    @EnvironmentObject var configManager: ConfigManager
    @EnvironmentObject var lm: LanguageManager
    @Environment(\.appDelegate) var appDelegate

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(lm.t(.appName)).font(.headline).padding(.bottom, 4)
            Divider()

            if let cfg = configManager.activeConfig {
                Text(cfg.name).font(.caption).foregroundStyle(.secondary)
            }

            Text(proxyVM.statusMessage)
                .font(.caption)
                .foregroundStyle(proxyVM.isRunning ? .green : .red)

            Divider()

            Button(proxyVM.isRunning ? lm.t(.menuStopProxy) : lm.t(.menuStartProxy)) {
                proxyVM.toggle()
            }

            // ✅ 使用 AppDelegate 显示窗口
            Button(lm.t(.menuSettings)) {
                appDelegate?.showMainWindow()
            }

            // 语言切换
            Divider()
            Button("\(lm.language.flag) \(lm.language.displayName)") {
                lm.toggle()
            }

            Divider()
            Button(lm.t(.menuQuit)) {
                proxyVM.stop()
                NSApp.terminate(nil)
            }
        }
        .padding(8)
        .frame(width: 200)
    }
}
