import XCTest
import WebKit
@testable import SafarierIOS

@MainActor
final class BrowserTests: XCTestCase {
    func testProfilesUseSeparatePersistentStores() throws {
        let first = BrowserProfile(name: "一")
        let second = BrowserProfile(name: "二")
        let a = try BrowserSession(profile: first)
        let b = try BrowserSession(profile: second)
        XCTAssertEqual(a.webView.configuration.websiteDataStore.identifier, first.id)
        XCTAssertEqual(b.webView.configuration.websiteDataStore.identifier, second.id)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertNil(a.webView.customUserAgent)
        XCTAssertTrue(a.webView.configuration.userContentController.userScripts.isEmpty)
        a.close(); b.close()
    }

    func testTemporaryStoreAndFailClosedProxy() throws {
        let proxy = BrowserProxy(kind: .socks5, host: "192.0.2.1", port: 1080)
        XCTAssertFalse(try proxy.configuration().allowFailover)
        let profile = BrowserProfile(name: "临时", temporary: true, proxy: proxy)
        let session = try BrowserSession(profile: profile)
        XCTAssertFalse(session.webView.configuration.websiteDataStore.isPersistent)
        XCTAssertEqual(session.webView.configuration.websiteDataStore.proxyConfigurations.count, 1)
        session.close()
    }

    func testInvalidProxyNeverCreatesSession() {
        for port in [0, -1, 65536] {
            let profile = BrowserProfile(name: "无效", proxy: BrowserProxy(kind: .httpConnect, host: "192.0.2.1", port: port))
            XCTAssertThrowsError(try BrowserSession(profile: profile))
        }
        XCTAssertThrowsError(try BrowserProxy(kind: .socks5, host: "https://example.com", port: 1080).configuration())
    }

    func testCookieIsolation() async throws {
        let a = try BrowserSession(profile: BrowserProfile(name: "A", temporary: true))
        let b = try BrowserSession(profile: BrowserProfile(name: "B", temporary: true))
        let cookie = try XCTUnwrap(HTTPCookie(properties: [.domain: "example.com", .path: "/", .name: "session", .value: "only-a"]))
        await a.webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie)
        let cookiesA = await a.webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        let cookiesB = await b.webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        XCTAssertTrue(cookiesA.contains { $0.name == "session" })
        XCTAssertFalse(cookiesB.contains { $0.name == "session" })
        a.close(); b.close()
    }

    func testProfilePersistenceAndCorruptionProtection() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("profiles.json")
        let first = ProfileStore(file: file)
        let profile = BrowserProfile(name: "保留登录")
        try first.add(profile)
        XCTAssertEqual(ProfileStore(file: file).profiles, [profile])
        try Data("broken".utf8).write(to: file)
        let broken = ProfileStore(file: file)
        XCTAssertFalse(broken.canWrite)
        XCTAssertThrowsError(try broken.add(profile))
        XCTAssertEqual(try String(contentsOf: file), "broken")
    }

    func testNavigationInput() {
        XCTAssertEqual(BrowserAddress.resolve("example.com")?.absoluteString, "https://example.com")
        XCTAssertNil(BrowserAddress.resolve("javascript:alert(1)"))
        XCTAssertNil(BrowserAddress.resolve("file:///etc/hosts"))
        XCTAssertNil(BrowserAddress.resolve("https://"))
        XCTAssertEqual(BrowserAddress.resolve("测试 搜索")?.host, "www.google.com")
    }
}
