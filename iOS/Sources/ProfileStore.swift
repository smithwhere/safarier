import Foundation
import Combine
import WebKit

@MainActor
final class ProfileStore: ObservableObject {
    @Published private(set) var profiles: [BrowserProfile] = []
    @Published var errorMessage: String?
    private let file: URL
    private(set) var canWrite = true

    init(file: URL? = nil) {
        self.file = file ?? URL.applicationSupportDirectory
            .appendingPathComponent("SafarierIOS", isDirectory: true)
            .appendingPathComponent("profiles.json")
        do {
            if FileManager.default.fileExists(atPath: self.file.path) {
                profiles = try JSONDecoder().decode([BrowserProfile].self, from: Data(contentsOf: self.file))
                guard Set(profiles.map(\.id)).count == profiles.count else {
                    throw CocoaError(.fileReadCorruptFile)
                }
            }
        } catch {
            canWrite = false
            errorMessage = "环境配置读取失败，已禁止覆盖原文件。"
        }
    }

    func add(_ profile: BrowserProfile) throws {
        guard canWrite else { throw CocoaError(.fileWriteNoPermission) }
        if let proxy = profile.proxy { _ = try proxy.configuration() }
        let updated = profiles + [profile]
        try persist(updated)
        profiles = updated
    }

    // 删除失败时保留记录，让用户重试；不留下无法管理的网站数据。
    func delete(_ profile: BrowserProfile) async {
        guard canWrite else { return }
        do {
            if !profile.temporary {
                _ = WKWebViewConfiguration()
                try await WKWebsiteDataStore.remove(forIdentifier: profile.id)
            }
            let updated = profiles.filter { $0.id != profile.id }
            try persist(updated)
            profiles = updated
        } catch {
            errorMessage = "删除失败。请关闭该环境后重试。"
        }
    }

    private func persist(_ profiles: [BrowserProfile]) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(profiles).write(to: file, options: [.atomic, .completeFileProtection])
    }
}
