import Foundation
import WebKit

@MainActor
final class ThreeFEmbeddedBrowserSession {
    static let shared = ThreeFEmbeddedBrowserSession()

    private weak var model: BrowserModel?
    private weak var webView: WKWebView?

    func attach(model: BrowserModel, webView: WKWebView) {
        self.model = model
        self.webView = webView
    }

    func navigate(to url: URL) {
        model?.navigate(to: url)
    }

    func history(_ action: String) -> Bool {
        guard let webView else { return false }
        switch action {
        case "back": guard webView.canGoBack else { return false }; webView.goBack(); return true
        case "forward": guard webView.canGoForward else { return false }; webView.goForward(); return true
        case "reload": guard webView.url != nil else { return false }; webView.reload(); return true
        default: return false
        }
    }

    func status() -> [String: Any] {
        guard let webView else { return ["available": false, "error": "3F Browser view is not ready"] }
        return [
            "available": true,
            "url": webView.url?.absoluteString ?? "about:blank",
            "title": webView.title ?? "",
            "canGoBack": webView.canGoBack,
            "canGoForward": webView.canGoForward
        ]
    }

    func readText(completion: @escaping (String?, String?) -> Void) {
        evaluate("document.body?.innerText?.slice(0, 12000) || ''", completion: completion)
    }

    func accessibilityTree(completion: @escaping (String?, String?) -> Void) {
        let script = """
        (() => {
          const elements = [...document.querySelectorAll('a[href],button,input,textarea,select,[role="button"],[role="link"],[role="textbox"]')];
          return elements.slice(0, 100).map((element, index) => {
            const id = 'oc-agent-' + (index + 1);
            element.dataset.threefAgentId = id;
            const label = element.getAttribute('aria-label') || element.innerText || element.value || element.placeholder || element.title || '';
            return '[' + id + '] ' + (element.getAttribute('role') || element.tagName.toLowerCase()) + ' ' + String(label).trim().replace(/\\s+/g, ' ').slice(0, 160);
          }).filter(line => !line.endsWith(' ')).join('\\n') + '\\n' + (document.body?.innerText || '').slice(0, 6000);
        })()
        """
        evaluate(script, completion: completion)
    }

    func act(_ action: String, completion: @escaping (String?, String?) -> Void) {
        let regex = try! NSRegularExpression(pattern: #"^(click|type|fill)\s+\[?(oc-agent-\d+)\]?\s*(.*)$"#, options: [.caseInsensitive, .dotMatchesLineSeparators])
        let range = NSRange(action.startIndex..., in: action)
        guard let captures = regex.firstMatch(in: action, range: range),
              let operationRange = Range(captures.range(at: 1), in: action),
              let idRange = Range(captures.range(at: 2), in: action),
              let valueRange = Range(captures.range(at: 3), in: action) else {
            completion(nil, "지원 동작: click, type, fill [oc-agent-N]")
            return
        }
        let operation = String(action[operationRange]).lowercased()
        let elementID = String(action[idRange])
        let value = String(action[valueRange])
        let idJSON = Self.jsonString(elementID)
        let script: String
        if operation == "click" {
            script = """
            (() => { const element = document.querySelector('[data-threef-agent-id=' + JSON.stringify(\(idJSON)) + ']'); if (!element) return 'element not found'; element.click(); return 'clicked'; })()
            """
        } else {
            script = """
            (() => { const element = document.querySelector('[data-threef-agent-id=' + JSON.stringify(\(idJSON)) + ']'); if (!element) return 'element not found'; if (!('value' in element)) return 'element is not editable'; const value = \(Self.jsonString(value)); const setter = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(element), 'value')?.set; setter ? setter.call(element, value) : (element.value = value); element.dispatchEvent(new Event('input', { bubbles: true })); element.dispatchEvent(new Event('change', { bubbles: true })); return 'typed'; })()
            """
        }
        evaluate(script, completion: completion)
    }

    private func evaluate(_ script: String, completion: @escaping (String?, String?) -> Void) {
        guard let webView else { completion(nil, "3F Browser view is not ready"); return }
        webView.evaluateJavaScript(script) { value, error in
            completion(value as? String, error?.localizedDescription)
        }
    }

    private static func jsonString(_ value: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [value])) ?? Data("[\"\"]".utf8)
        let array = String(data: data, encoding: .utf8) ?? "[\"\"]"
        return String(array.dropFirst().dropLast())
    }
}
