import SwiftUI
import WebKit

@main
struct SafarierIOSApp: App {
    @StateObject private var profiles = ProfileStore()
    var body: some Scene {
        WindowGroup { ProfileList(store: profiles) }
    }
}

struct ProfileList: View {
    @ObservedObject var store: ProfileStore
    @State private var adding = false
    @State private var selection: BrowserProfile?
    @State private var deleting: BrowserProfile?
    @State private var busy = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.profiles) { profile in
                        Button {
                            selection = profile
                        } label: {
                            HStack {
                                Image(systemName: profile.temporary ? "eye.slash" : "globe")
                                    .foregroundStyle(.blue)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(profile.name).foregroundStyle(.primary)
                                    Text("\(profile.temporary ? "临时环境" : "持久环境") · \(profile.proxy == nil ? "直连" : "独立代理")")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }.padding(.vertical, 6)
                        }
                        .swipeActions {
                            Button("删除", role: .destructive) { deleting = profile }
                        }
                    }
                } header: { Text("我的环境") } footer: {
                    Text("每个环境使用独立的网站数据存储。临时环境关闭后不保留网站会话。")
                }
                Section("iOS 版本能力") {
                    Label("本机 Apple WebKit，无需远程 Mac", systemImage: "iphone")
                    Label("不注入设备指纹伪造脚本", systemImage: "checkmark.shield")
                    Text("本版不模拟 Mac。未验证 Safari 高级反指纹加噪，不承诺独立应用进程或物理隔离。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Safarier")
            .toolbar {
                Button { adding = true } label: { Label("新建环境", systemImage: "plus") }
                    .disabled(!store.canWrite || busy)
            }
            .disabled(busy)
            .sheet(isPresented: $adding) { ProfileEditor(store: store) }
            .fullScreenCover(item: $selection) { profile in BrowserHost(profile: profile) }
            .confirmationDialog("删除环境及其网站数据？", isPresented: Binding(
                get: { deleting != nil }, set: { if !$0 { deleting = nil } }
            ), titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    guard let profile = deleting else { return }
                    busy = true
                    Task {
                        await store.delete(profile)
                        busy = false
                        deleting = nil
                    }
                }
            }
            .alert("环境管理", isPresented: Binding(
                get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } }
            )) { Button("确定", role: .cancel) {} } message: { Text(store.errorMessage ?? "") }
        }
    }
}

struct ProfileEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: ProfileStore
    @State private var name = ""
    @State private var temporary = false
    @State private var useProxy = false
    @State private var kind = BrowserProxy.Kind.socks5
    @State private var host = ""
    @State private var port = "1080"
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("环境") {
                    TextField("环境名称", text: $name)
                    Toggle("临时环境", isOn: $temporary)
                }
                Section {
                    Toggle("使用独立代理", isOn: $useProxy)
                    if useProxy {
                        Picker("协议", selection: $kind) {
                            Text("SOCKS5").tag(BrowserProxy.Kind.socks5)
                            Text("HTTP CONNECT").tag(BrowserProxy.Kind.httpConnect)
                        }
                        TextField("主机名或 IP", text: $host)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        TextField("端口", text: $port).keyboardType(.numberPad)
                    }
                } header: { Text("网络") } footer: {
                    Text(useProxy
                         ? "当前支持无需认证的代理。连接失败不回退直连。订阅协议与代理认证尚未移植。"
                         : "此环境使用设备当前网络。需要独立出口时，请先配置代理。")
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("新建环境")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        do {
            var profile = BrowserProfile(name: name.trimmingCharacters(in: .whitespacesAndNewlines), temporary: temporary)
            if useProxy {
                guard let value = Int(port) else { throw BrowserError.invalidProxy }
                profile.proxy = BrowserProxy(kind: kind, host: host.trimmingCharacters(in: .whitespacesAndNewlines), port: value)
            }
            try store.add(profile)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct BrowserHost: View {
    let profile: BrowserProfile
    @State private var session: BrowserSession?
    @State private var failure: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let session {
                BrowserScreen(session: session) {
                    session.close()
                    self.session = nil
                    dismiss()
                }
            } else if let failure {
                ContentUnavailableView {
                    Label("环境未打开", systemImage: "exclamationmark.shield")
                } description: { Text(failure) } actions: { Button("返回") { dismiss() } }
            } else { ProgressView("正在打开环境") }
        }
        .task {
            guard session == nil, failure == nil else { return }
            do { session = try BrowserSession(profile: profile) }
            catch { failure = error.localizedDescription }
        }
        .onDisappear { session?.close(); session = nil }
    }
}

struct BrowserScreen: View {
    @ObservedObject var session: BrowserSession
    let close: () -> Void
    @FocusState private var addressFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: close) { Image(systemName: "chevron.down") }.accessibilityLabel("关闭环境")
                Text(session.profile.name).font(.caption).lineLimit(1)
                Spacer()
                Text(session.profile.proxy == nil ? "直连" : "代理").font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal).padding(.top, 8)
            HStack {
                TextField("搜索或输入网址", text: $session.address)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .keyboardType(.webSearch).submitLabel(.go).focused($addressFocused)
                    .onSubmit { addressFocused = false; session.navigate() }
                Button {
                    addressFocused = false
                    session.navigate()
                } label: { Image(systemName: "arrow.right.circle.fill") }.accessibilityLabel("前往")
            }.padding(10).background(.quaternary, in: RoundedRectangle(cornerRadius: 12)).padding(12)
            if session.progress > 0 && session.progress < 1 { ProgressView(value: session.progress) }
            if let error = session.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red).padding(8)
            }
            BrowserSurface(session: session)
            HStack {
                Button { session.webView.goBack() } label: { Image(systemName: "chevron.left") }
                    .disabled(!session.canGoBack).accessibilityLabel("后退")
                Spacer()
                Button { session.webView.goForward() } label: { Image(systemName: "chevron.right") }
                    .disabled(!session.canGoForward).accessibilityLabel("前进")
                Spacer()
                Button { session.errorMessage = nil; session.webView.reload() } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel("刷新")
            }.padding()
        }
    }
}
