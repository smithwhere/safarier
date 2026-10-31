import Foundation
import Network

struct BrowserProfile: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var temporary = false
    var proxy: BrowserProxy?
}

struct BrowserProxy: Codable, Equatable {
    enum Kind: String, Codable, CaseIterable { case socks5, httpConnect }
    var kind: Kind
    var host: String
    var port: Int

    func configuration() throws -> ProxyConfiguration {
        let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanHost.isEmpty, cleanHost == host,
              !host.contains(where: { $0.isWhitespace }),
              !host.contains("/"), !host.contains("@"),
              (1...65535).contains(port), let endpointPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            throw BrowserError.invalidProxy
        }
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: endpointPort)
        var result: ProxyConfiguration
        switch kind {
        case .socks5: result = ProxyConfiguration(socksv5Proxy: endpoint)
        case .httpConnect: result = ProxyConfiguration(httpCONNECTProxy: endpoint, tlsOptions: nil)
        }
        result.allowFailover = false
        return result
    }
}

enum BrowserError: LocalizedError {
    case invalidProxy, invalidAddress
    var errorDescription: String? {
        switch self {
        case .invalidProxy: return "代理地址或端口无效，已阻止打开环境。"
        case .invalidAddress: return "请输入有效的 HTTP 或 HTTPS 网址。"
        }
    }
}

enum BrowserAddress {
    static func resolve(_ input: String) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.contains("://") {
            guard let url = URL(string: text), permits(url), url.host?.isEmpty == false else { return nil }
            return url
        }
        // 禁止把脚本或外部应用协议当作导航执行。
        if text.contains(":"), !text.contains("://") { return nil }
        if !text.contains(where: { $0.isWhitespace }), text.contains(".") {
            return URL(string: "https://" + text)
        }
        var components = URLComponents(string: "https://www.google.com/search")!
        components.queryItems = [URLQueryItem(name: "q", value: text)]
        return components.url
    }

    static func permits(_ url: URL) -> Bool {
        ["https", "http"].contains(url.scheme?.lowercased() ?? "")
    }
}
