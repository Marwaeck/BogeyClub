import AppKit
import WebKit
import UniformTypeIdentifiers
import BogeyCore
import BogeyScan

/// Zeigt die Bogey-Club-Oberfläche (aus dem App-Paket) und beantwortet ihre Anfragen:
/// Daten lesen/schreiben, Bilder ablegen, Dateien sichern, Scorekarten lesen.
@MainActor
final class WebController: NSViewController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandlerWithReply {
    static let origin = URL(string: "bogey://app/index.html")!

    private let store: Store
    private var webView: WKWebView!

    init(store: Store) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Ordner mit index.html, runtime.js und vendor/ – im App-Paket unter Resources/web.
    static var webFolder: URL {
        if let custom = ProcessInfo.processInfo.environment["BOGEY_WEB_DIR"], !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        return Bundle.main.resourceURL!.appendingPathComponent("web", isDirectory: true)
    }

    override func loadView() {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(SchemeHandler(store: store, webFolder: Self.webFolder), forURLScheme: "bogey")
        config.userContentController.addScriptMessageHandler(self, contentWorld: .page, name: "bogey")
        config.websiteDataStore = .nonPersistent()   // alle Daten liegen im Datenordner, nicht im Browser-Speicher

        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1100, height: 820), configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsMagnification = true
        webView.allowsBackForwardNavigationGestures = false
        if #available(macOS 13.3, *) { webView.isInspectable = true }
        webView.pageZoom = CGFloat(UserDefaults.standard.object(forKey: "pageZoom") as? Double ?? 1)
        view = webView
        webView.load(URLRequest(url: Self.origin))
    }

    func reload() { webView.load(URLRequest(url: Self.origin)) }

    func zoom(to value: CGFloat) {
        webView.pageZoom = min(2, max(0.6, value))
        UserDefaults.standard.set(Double(webView.pageZoom), forKey: "pageZoom")
    }
    func zoom(by delta: CGFloat) { zoom(to: webView.pageZoom + delta) }

    // MARK: Navigation – externe Links im Standard-Browser öffnen

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { return decisionHandler(.cancel) }
        if ["bogey", "blob", "data", "about"].contains(url.scheme ?? "") { return decisionHandler(.allow) }
        NSWorkspace.shared.open(url)
        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, ["http", "https", "mailto"].contains(url.scheme ?? "") {
            NSWorkspace.shared.open(url)
        }
        return nil
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { reload() }

    // MARK: Datei wählen (<input type="file">)

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.beginSheetModal(for: view.window!) { result in
            completionHandler(result == .OK ? panel.urls : nil)
        }
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor () -> Void) {
        let alert = NSAlert(); alert.messageText = message
        alert.beginSheetModal(for: view.window!) { _ in completionHandler() }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (Bool) -> Void) {
        let alert = NSAlert(); alert.messageText = message
        alert.addButton(withTitle: "OK"); alert.addButton(withTitle: "Abbrechen")
        alert.beginSheetModal(for: view.window!) { completionHandler($0 == .alertFirstButtonReturn) }
    }

    // MARK: Brücke zu runtime.js

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping @MainActor (Any?, String?) -> Void) {
        guard let body = message.body as? [String: Any], let cmd = body["cmd"] as? String else {
            return replyHandler(["error": "bad_request"], nil)
        }
        let str = { (k: String) in body[k] as? String ?? "" }
        do {
            switch cmd {
            case "db.load":
                replyHandler(try store.allJSON(), nil)
            case "db.set":
                try store.set(str("coll"), id: str("id"), json: str("data"))
                replyHandler([:], nil)
            case "db.delete":
                try store.delete(str("coll"), id: str("id"))
                replyHandler([:], nil)
            case "assets.upload":
                guard let bytes = Data(base64Encoded: str("base64")) else { return replyHandler(["error": "unsupported_type"], nil) }
                let id = try store.addPhoto(bytes, type: str("type"))
                replyHandler(["id": id, "url": "/_blob/\(id)"], nil)
            case "assets.delete":
                store.deletePhoto(str("id"))
                replyHandler([:], nil)
            case "download.save":
                saveFile(name: str("filename"), base64: str("base64"), reply: replyHandler)
            case "scan":
                let images = (body["images"] as? [String] ?? []).compactMap { Data(base64Encoded: $0) }
                Task.detached(priority: .userInitiated) {
                    let reply: Any
                    do { reply = try ScorecardReader.read(images: images).jsonObject } catch { reply = ["error": "image_rejected"] }
                    let sendable = SendableBox(reply)
                    await MainActor.run { replyHandler(sendable.value, nil) }
                }
            default:
                replyHandler(["error": "unknown_command"], nil)
            }
        } catch {
            replyHandler(["error": "error"], nil)
        }
    }

    private func saveFile(name: String, base64: String, reply: @escaping @MainActor (Any?, String?) -> Void) {
        guard let data = Data(base64Encoded: base64) else { return reply(["error": "error"], nil) }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        if let ext = name.split(separator: ".").last, let type = UTType(filenameExtension: String(ext)) {
            panel.allowedContentTypes = [type]
        }
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        panel.beginSheetModal(for: view.window!) { result in
            guard result == .OK, let url = panel.url else { return reply(["error": "declined"], nil) }
            do { try data.write(to: url, options: .atomic); reply([:], nil) } catch { reply(["error": "error"], nil) }
        }
    }
}

/// Reicht ein Ergebnis aus dem Hintergrund an den Hauptthread weiter (nur JSON-Werte).
struct SendableBox: @unchecked Sendable { let value: Any; init(_ v: Any) { value = v } }

/// Liefert die App-Dateien unter bogey://app/… und die Bilder unter bogey://app/_blob/<id>.
final class SchemeHandler: NSObject, WKURLSchemeHandler {
    private let store: Store
    private let webFolder: URL

    init(store: Store, webFolder: URL) {
        self.store = store
        self.webFolder = webFolder.standardizedFileURL
    }

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url else { return task.didFailWithError(URLError(.badURL)) }
        var path = url.path
        if path.isEmpty || path == "/" { path = "/index.html" }

        var file: URL?, type = "application/octet-stream"
        if path.hasPrefix("/_blob/") {
            if let p = store.photo(String(path.dropFirst(7))) { file = p.url; type = p.type }
        } else {
            let candidate = webFolder.appendingPathComponent(String(path.dropFirst())).standardizedFileURL
            if candidate.path.hasPrefix(webFolder.path + "/") {
                file = candidate
                type = UTType(filenameExtension: candidate.pathExtension)?.preferredMIMEType ?? type
                if candidate.pathExtension == "js" { type = "text/javascript" }
                if candidate.pathExtension == "css" { type = "text/css" }
                if candidate.pathExtension == "woff2" { type = "font/woff2" }
            }
        }

        guard let file, let data = try? Data(contentsOf: file) else {
            let res = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/plain"])!
            task.didReceive(res); task.didReceive(Data()); task.didFinish()
            return
        }
        if type.hasPrefix("text/") { type += "; charset=utf-8" }
        let isHead = task.request.httpMethod == "HEAD"
        let res = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                  headerFields: ["Content-Type": type, "Content-Length": String(data.count), "Cache-Control": "no-store"])!
        task.didReceive(res)
        task.didReceive(isHead ? Data() : data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}
}
