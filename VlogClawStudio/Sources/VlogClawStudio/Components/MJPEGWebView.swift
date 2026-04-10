import SwiftUI
import WebKit

struct MJPEGWebView: NSViewRepresentable {
    let streamURL: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        load(streamURL, in: webView)
        context.coordinator.loadedURL = streamURL
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedURL != streamURL else { return }
        load(streamURL, in: webView)
        context.coordinator.loadedURL = streamURL
    }

    private func load(_ url: URL, in webView: WKWebView) {
        let html = """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <style>
            html, body {
              margin: 0;
              width: 100%;
              height: 100%;
              overflow: hidden;
              background: radial-gradient(circle at top, #1f2a36 0%, #05070b 76%);
            }
            .frame {
              width: 100%;
              height: 100%;
              display: flex;
              align-items: center;
              justify-content: center;
              padding: 12px;
              box-sizing: border-box;
            }
            img {
              width: 100%;
              height: 100%;
              object-fit: contain;
              border-radius: 18px;
              box-shadow: 0 20px 48px rgba(0, 0, 0, 0.45);
              background: rgba(255,255,255,0.02);
            }
          </style>
        </head>
        <body>
          <div class="frame">
            <img src="\(url.absoluteString)" alt="Live iPhone preview" />
          </div>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    final class Coordinator {
        var loadedURL: URL?
    }
}
