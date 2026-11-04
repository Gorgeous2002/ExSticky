import Cocoa
import WebKit

@main
struct MarkdownEditorChecks {
    static func wait(_ predicate: () -> Bool) {
        let deadline = Date().addingTimeInterval(20)
        while !predicate() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        precondition(predicate(), "Timed out waiting for WebKit")
    }
    static func evaluate(_ web: WKWebView, _ script: String) -> Any? {
        var done = false
        var output: Any?
        var failure: Error?
        web.evaluateJavaScript(script) { value, error in output = value; failure = error; done = true }
        wait { done }
        precondition(failure == nil, "JavaScript failed: \(String(describing: failure))")
        return output
    }
    static func main() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 580, height: 540), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        let editor = MarkdownEditor(frame: window.contentView!.bounds)
        let source = "# Markdown 实时编辑\n\n1. 第一层\n   1. 第二层\n      1. 第三层 a\n      2. 第三层 b\n   2. 第二层 ii\n2. 第一层 2\n\n行内公式 $E=mc^2$\n\n$$\n\\sum_{i=1}^{n}i=\\frac{n(n+1)}{2}\n$$"
        editor.sourceProvider = { source }
        window.contentView = editor
        window.makeKeyAndOrderFront(nil)
        editor.load()
        wait { editor.webView.url != nil && !editor.webView.isLoading }
        wait { (evaluate(editor.webView, "typeof window.setMarkdown") as? String) == "function" }
        precondition(evaluate(editor.webView, "document.querySelectorAll('ol ol ol > li').length") as? Int == 2)
        let styles = evaluate(editor.webView, "['ol > li','ol ol > li','ol ol ol > li'].map(s=>getComputedStyle(document.querySelector(s), '::before').content).join('|')") as? String
        precondition((styles?.contains("counter(list-item)") == true || styles?.contains("decimal") == true) && styles?.contains("lower-roman") == true && styles?.contains("lower-alpha") == true, styles ?? "no list counters")
        precondition(evaluate(editor.webView, "document.querySelectorAll('.katex').length") as? Int == 2)
        precondition(evaluate(editor.webView, "document.querySelector('.ProseMirror').isContentEditable") as? Bool == true)
        // Empty list items must place the insertion caret after generated numbering.
        // An inline paragraph paints its empty caret before ::before in WebKit.
        let emptyLayout = evaluate(editor.webView, """
            (() => {
                const fixture = document.createElement('div'); fixture.className = 'ProseMirror';
                fixture.innerHTML = '<ol><li><p><br></p><ol><li><p><br></p><ol><li><p><br></p></li></ol></li></ol></li></ol>';
                document.body.append(fixture);
                const ok = [...fixture.querySelectorAll('p')].every(p => {
                    const text = p.getBoundingClientRect(), item = p.parentElement.getBoundingClientRect();
                    return text.x > item.x && text.height > 0
                        && getComputedStyle(p).display === 'block'
                        && getComputedStyle(p.parentElement).counterIncrement === 'list-item 1';
                });
                fixture.remove(); return ok;
            })()
            """) as? Bool
        precondition(emptyLayout == true, "Empty list editing boxes must follow markers at all three depths")
        // Programmatic source loading must not rewrite the stored Markdown.
        var saved: String?
        editor.onChange = { saved = $0 }
        editor.setSource("1. 原文\n2. 修改")
        _ = evaluate(editor.webView, "document.querySelector('.ProseMirror').focus()")
        precondition(saved == nil)
        // Browser editing is bridged back to the native persistence string.
        _ = evaluate(editor.webView, "document.execCommand('selectAll'); document.execCommand('insertText', false, '同步测试😀');")
        wait { saved?.contains("同步测试😀") == true }
        editor.setSource(source)
        _ = evaluate(editor.webView, "document.body.offsetHeight")
        _ = evaluate(editor.webView, "document.documentElement.style.backgroundColor = 'white'; document.documentElement.style.colorScheme = 'light'; document.body.style.color = 'black';")
        var painted = false
        editor.webView.callAsyncJavaScript("await document.fonts.ready; await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));", arguments: [:], in: nil, in: .page) { _ in painted = true }
        wait { painted }
        var captured = false
        editor.webView.takeSnapshot(with: nil) { image, error in
            if let image = image, let data = image.tiffRepresentation, let rep = NSBitmapImageRep(data: data), let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: "/tmp/exsticky-markdown-preview.png"))
            }
            captured = true
        }
        wait { captured }
        print("PASS: real WKWebView bundled assets, empty list editing boxes at three depths, editable DOM, decimal/roman/alpha markers, KaTeX rendering, native Markdown bridge.")
        window.orderOut(nil)
    }
}
