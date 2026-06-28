// Copyright 2026 Andrew Voirol. Apache-2.0
// Copyright 2026 Andrew Voirol
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import SwiftUI
import WebKit

// MARK: - Canvas Web View

/// A sandboxed WKWebView that renders HTML content from model output.
///
/// Security model:
/// - JavaScript is enabled (required for interactive artifacts).
/// - Network access is blocked via `WKContentRuleList` — all external
///   resource loads (`fetch`, `XMLHttpRequest`, `<img src="...">`) are denied.
/// - Only `loadHTMLString` is used — no URL navigation.
///
/// Platform adaptation:
/// - macOS: `NSViewRepresentable`
/// - iOS: `UIViewRepresentable`

#if os(macOS)

struct CanvasWebView: NSViewRepresentable {
    let htmlContent: String
    let onHeightChange: ((CGFloat) -> Void)?

    init(htmlContent: String, onHeightChange: ((CGFloat) -> Void)? = nil) {
        self.htmlContent = htmlContent
        self.onHeightChange = onHeightChange
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onHeightChange: onHeightChange)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = Self.createConfiguration(coordinator: context.coordinator)
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.setupContentRules(for: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let injectedHTML = CanvasDarkModeCSS.inject(into: htmlContent)
        webView.loadHTMLString(injectedHTML, baseURL: nil)
    }

    static func createConfiguration(coordinator: Coordinator) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        // Add script message handler for content height reporting
        let userController = WKUserContentController()
        userController.add(coordinator, name: "canvasResize")

        // Inject ResizeObserver script to report content height
        let resizeScript = WKUserScript(
            source: Self.resizeObserverScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        userController.addUserScript(resizeScript)
        config.userContentController = userController

        return config
    }

    /// JavaScript injected at document end to observe content size changes
    /// and report them back to Swift via `webkit.messageHandlers.canvasResize`.
    static let resizeObserverScript = """
    (function() {
        const observer = new ResizeObserver(entries => {
            for (let entry of entries) {
                const height = entry.target.scrollHeight;
                window.webkit.messageHandlers.canvasResize.postMessage({ height: height });
            }
        });
        observer.observe(document.body);
        // Initial height report
        setTimeout(() => {
            window.webkit.messageHandlers.canvasResize.postMessage({
                height: document.body.scrollHeight
            });
        }, 100);
    })();
    """
}

#else // iOS

struct CanvasWebView: UIViewRepresentable {
    let htmlContent: String
    let onHeightChange: ((CGFloat) -> Void)?

    init(htmlContent: String, onHeightChange: ((CGFloat) -> Void)? = nil) {
        self.htmlContent = htmlContent
        self.onHeightChange = onHeightChange
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onHeightChange: onHeightChange)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = Self.createConfiguration(coordinator: context.coordinator)
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        context.coordinator.setupContentRules(for: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let injectedHTML = CanvasDarkModeCSS.inject(into: htmlContent)
        webView.loadHTMLString(injectedHTML, baseURL: nil)
    }

    static func createConfiguration(coordinator: Coordinator) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        // Add script message handler for content height reporting
        let userController = WKUserContentController()
        userController.add(coordinator, name: "canvasResize")

        // Inject ResizeObserver script to report content height
        let resizeScript = WKUserScript(
            source: Self.resizeObserverScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        userController.addUserScript(resizeScript)
        config.userContentController = userController

        return config
    }

    static let resizeObserverScript = """
    (function() {
        const observer = new ResizeObserver(entries => {
            for (let entry of entries) {
                const height = entry.target.scrollHeight;
                window.webkit.messageHandlers.canvasResize.postMessage({ height: height });
            }
        });
        observer.observe(document.body);
        // Initial height report
        setTimeout(() => {
            window.webkit.messageHandlers.canvasResize.postMessage({
                height: document.body.scrollHeight
            });
        }, 100);
    })();
    """
}

#endif

// MARK: - Coordinator (Shared)

extension CanvasWebView {
    /// Coordinator handles WKScriptMessageHandler for content height reporting
    /// and sets up content blocking rules to prevent network access.
    class Coordinator: NSObject, WKScriptMessageHandler {
        let onHeightChange: ((CGFloat) -> Void)?

        init(onHeightChange: ((CGFloat) -> Void)?) {
            self.onHeightChange = onHeightChange
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "canvasResize",
                  let body = message.body as? [String: Any],
                  let height = body["height"] as? CGFloat else { return }
            DispatchQueue.main.async { [weak self] in
                self?.onHeightChange?(height)
            }
        }

        /// Compiles and installs a WKContentRuleList that blocks all network requests.
        /// This is the primary security boundary for Canvas — no phone-home, no external resources.
        func setupContentRules(for webView: WKWebView) {
            // Block all network resource types
            let blockRules = """
            [{
                "trigger": { "url-filter": ".*" },
                "action": { "type": "block" }
            }]
            """
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: "CanvasNetworkBlock",
                encodedContentRuleList: blockRules
            ) { ruleList, error in
                if let ruleList = ruleList {
                    webView.configuration.userContentController.add(ruleList)
                }
                // Silently fail — the content will render without network blocking
                // rather than failing to render at all. Logged in debug only.
                #if DEBUG
                if let error = error {
                    print("[CanvasWebView] Content rule compilation failed: \(error)")
                }
                #endif
            }
        }
    }
}
