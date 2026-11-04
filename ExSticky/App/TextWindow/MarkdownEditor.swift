import Cocoa
import WebKit

/// Keeps Markdown as the persistence format while WebKit owns the live editing surface.
final class MarkdownEditor: NSView, WKNavigationDelegate, WKScriptMessageHandler {
    private(set) var webView: WKWebView!
    var onChange: ((String) -> Void)?
    var sourceProvider: (() -> String)?
    private var ready = false
    private var selectionBackground = "Highlight"
    private var selectionForeground = "HighlightText"
    private let errorLabel = NSTextField(wrappingLabelWithString: String(localized: "Markdown editor could not load. Switch to Source to continue editing."))

    override init(frame: NSRect) {
        super.init(frame: frame)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: configuration)
        // Register through a weak proxy: WKUserContentController retains its handlers.
        configuration.userContentController.add(WeakScriptHandler(self), name: "markdownChanged")
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        addSubview(webView)
        webView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: leadingAnchor), webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: topAnchor), webView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        errorLabel.isHidden = true
        addSubview(errorLabel)
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            errorLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            errorLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            errorLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func load() {
        guard let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Markdown") else {
            errorLabel.isHidden = false
            return
        }
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    func setSource(_ source: String) {
        guard ready else { return }
        webView.callAsyncJavaScript("window.setMarkdown(source)", arguments: ["source": source], in: nil, in: .page) { [weak self] result in
            if case .failure = result { self?.errorLabel.isHidden = false }
        }
    }

    func currentSource(_ completion: @escaping (String) -> Void) {
        guard ready else { completion(sourceProvider?() ?? ""); return }
        webView.callAsyncJavaScript("return window.getMarkdown()", arguments: [:], in: nil, in: .page) { [weak self] result in
            if case .success(let value) = result, let source = value as? String { completion(source) }
            else { completion(self?.sourceProvider?() ?? "") }
        }
    }

    func updateSelection(background: NSColor, foreground: NSColor) {
        func css(_ color: NSColor) -> String {
            let rgb = color.usingColorSpace(.sRGB) ?? .black
            return "rgb(\(Int(rgb.redComponent * 255)),\(Int(rgb.greenComponent * 255)),\(Int(rgb.blueComponent * 255)))"
        }
        selectionBackground = css(background)
        selectionForeground = css(foreground)
        applySelection()
    }

    private func applySelection() {
        guard ready else { return }
        webView.callAsyncJavaScript("document.documentElement.style.setProperty('--selection-background', background); document.documentElement.style.setProperty('--selection-foreground', foreground);",
                                   arguments: ["background": selectionBackground, "foreground": selectionForeground], in: nil, in: .page, completionHandler: nil)
    }

    func updateStyle(font: NSFont?) {
        guard ready else { return }
        webView.callAsyncJavaScript("document.body.style.fontSize = size + 'px'; document.body.style.fontFamily = family;",
                                   arguments: ["size": font?.pointSize ?? CGFloat(UserSettings.text.size),
                                               "family": font?.familyName ?? UserSettings.text.font], in: nil, in: .page, completionHandler: nil)
    }

    func command(_ name: String) {
        guard ready else { return }
        webView.callAsyncJavaScript("window.editorCommand(name)", arguments: ["name": name], in: nil, in: .page, completionHandler: nil)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let source = message.body as? String else { return }
        onChange?(source)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        ready = true
        setSource(sourceProvider?() ?? "")
        updateStyle(font: nil)
        applySelection()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { errorLabel.isHidden = false }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { errorLabel.isHidden = false }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        ready = false
        load()
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.navigationType == .linkActivated {
            if let url = navigationAction.request.url, ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") {
                NSWorkspace.shared.open(url)
            }
            decisionHandler(.cancel)
        } else {
            decisionHandler(navigationAction.request.url?.isFileURL == true ? .allow : .cancel)
        }
    }
}

private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
