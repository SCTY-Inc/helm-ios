import SwiftUI
import WebKit

/// Decides what a tapped link means inside a rendered document.
enum DocumentLink: Equatable {
    case anchor                 // same-document #fragment → let the web view scroll
    case document(String)       // relative .md/.html → open in Helm at this SFTP path
    case ignore

    /// Pure resolution logic for non-external links (unit-tested). `resolvedPath` is
    /// the URL path WebKit produced after resolving the link against the base URL.
    /// http(s) links are handled by the caller before this runs.
    static func classify(
        resolvedPath: String,
        fragment: String?,
        currentPath: String
    ) -> DocumentLink {
        let originalWasAbsolute = currentPath.hasPrefix("/")
        let decoded = resolvedPath.removingPercentEncoding ?? resolvedPath
        let sftpPath: String
        if originalWasAbsolute {
            sftpPath = decoded
        } else {
            sftpPath = decoded.hasPrefix("/") ? String(decoded.dropFirst()) : decoded
        }

        // A fragment on the current document is an in-page anchor.
        if fragment != nil, sftpPath == currentPath {
            return .anchor
        }

        switch RemoteFileFormat(path: sftpPath) {
        case .markdown, .html:
            return .document(sftpPath)
        case .none:
            return .ignore
        }
    }
}

/// A `WKWebView` wrapper for rendered markdown / HTML. Relative document links open
/// in Helm via `onOpenDocument`; external links open in Safari; in-page anchors
/// scroll. `scrollAnchor` lets the TOC jump to a heading.
struct DocumentWebView: UIViewRepresentable {
    let html: String
    /// SFTP path of the current document (drives base URL + relative-link resolution).
    let documentPath: String?
    var onOpenDocument: ((String) -> Void)?
    @Binding var scrollAnchor: String?
    @AppStorage("helm.readerTextScalePercent") private var textScalePercent: Int = 100

    init(
        html: String,
        documentPath: String? = nil,
        onOpenDocument: ((String) -> Void)? = nil,
        scrollAnchor: Binding<String?> = .constant(nil)
    ) {
        self.html = html
        self.documentPath = documentPath
        self.onOpenDocument = onOpenDocument
        self._scrollAnchor = scrollAnchor
    }

    private static let scheme = "helm-doc"

    private var baseURL: URL? {
        guard let documentPath else { return nil }
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = ""
        components.path = documentPath.hasPrefix("/") ? documentPath : "/" + documentPath
        return components.url
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onOpenDocument: onOpenDocument, currentPath: documentPath)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onOpenDocument = onOpenDocument
        context.coordinator.currentPath = documentPath
        context.coordinator.textScalePercent = textScalePercent

        if context.coordinator.lastHTML != html {
            context.coordinator.lastHTML = html
            webView.loadHTMLString(html, baseURL: baseURL)
        } else {
            context.coordinator.applyTextScale(to: webView)
        }

        if let anchor = scrollAnchor {
            let safe = anchor.replacingOccurrences(of: "'", with: "\\'")
            webView.evaluateJavaScript(
                "var e=document.getElementById('\(safe)'); if(e){e.scrollIntoView({behavior:'smooth',block:'start'});}"
            )
            DispatchQueue.main.async { scrollAnchor = nil }
        }
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastHTML: String?
        var onOpenDocument: ((String) -> Void)?
        var currentPath: String?
        var textScalePercent: Int = 100

        init(onOpenDocument: ((String) -> Void)?, currentPath: String?) {
            self.onOpenDocument = onOpenDocument
            self.currentPath = currentPath
        }

        func applyTextScale(to webView: WKWebView) {
            webView.evaluateJavaScript(
                "document.documentElement.style.webkitTextSizeAdjust='\(textScalePercent)%';"
            )
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            applyTextScale(to: webView)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            guard navigationAction.navigationType == .linkActivated,
                  let url = navigationAction.request.url else {
                return .allow
            }

            if let scheme = url.scheme, scheme == "http" || scheme == "https" {
                await UIApplication.shared.open(url)
                return .cancel
            }

            let link = DocumentLink.classify(
                resolvedPath: url.path,
                fragment: url.fragment,
                currentPath: currentPath ?? ""
            )

            switch link {
            case .anchor:
                return .allow
            case let .document(path):
                onOpenDocument?(path)
                return .cancel
            case .ignore:
                return .cancel
            }
        }
    }
}
