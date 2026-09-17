import SwiftUI
import WebKit

struct BrowserExtractorView: View {
    @State private var inputURL = "https://"
    @State private var browserURL: URL?
    @State private var pageURL: URL?
    @State private var discovered: [MediaCandidate] = []
    @State private var isLoading = false
    @State private var showResults = false
    @State private var probeToken = 0
    @FocusState private var urlFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                controlBar
                Divider()

                if let browserURL {
                    BrowserWebView(
                        initialURL: browserURL,
                        discovered: $discovered,
                        pageURL: $pageURL,
                        isLoading: $isLoading,
                        probeToken: $probeToken
                    )
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "safari")
                            .font(.system(size: 46))
                            .foregroundStyle(.secondary)

                        Text("输入网址开始")
                            .font(.headline)

                        Text("在浏览器中打开页面并播放视频，应用会自动收集页面中的视频、音频和图片地址。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("浏览器提取")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        probeToken += 1
                        showResults = true
                    } label: {
                        Text("提取")
                    }
                }
            }
            .sheet(isPresented: $showResults) {
                NavigationStack {
                    ResultsView(candidates: $discovered, pageURL: pageURL)
                }
            }
        }
    }

    private var controlBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "lock")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("网址", text: $inputURL)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($urlFocused)
                    .onSubmit(go)

                if !inputURL.isEmpty {
                    Button {
                        inputURL = ""
                        discovered = []
                        browserURL = nil
                        pageURL = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))

            Button("前往", action: go)
                .buttonStyle(.borderedProminent)
                .disabled(inputURL.trimmingCharacters(in: .whitespaces).isEmpty)

            if isLoading {
                ProgressView()
            }
        }
        .padding(12)
        .liquidGlassCard(cornerRadius: 20, shadowRadius: 10)
        .padding(.horizontal)
    }

    private func go() {
        urlFocused = false
        guard let url = VideoExtractorEngine.normalizedURL(from: inputURL) else { return }
        discovered = []
        browserURL = url
        pageURL = url
    }
}

private struct BrowserWebView: UIViewRepresentable {
    let initialURL: URL
    @Binding var discovered: [MediaCandidate]
    @Binding var pageURL: URL?
    @Binding var isLoading: Bool
    @Binding var probeToken: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(
            discovered: $discovered,
            pageURL: $pageURL,
            isLoading: $isLoading,
            probeToken: probeToken
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.customUserAgent = VideoExtractorEngine.userAgent
        webView.allowsBackForwardNavigationGestures = true

        let controller = webView.configuration.userContentController
        controller.removeScriptMessageHandler(forName: "mediaProbe")
        controller.add(context.coordinator, name: "mediaProbe")

        let script = WKUserScript(
            source: BrowserWebView.probeScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        controller.addUserScript(script)

        let sniffScript = WKUserScript(
            source: BrowserWebView.sniffScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        controller.addUserScript(sniffScript)

        webView.load(URLRequest(url: initialURL))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastProbeToken != probeToken {
            context.coordinator.lastProbeToken = probeToken
            context.coordinator.runProbe(webView)
        }

        if webView.url == nil {
            webView.load(URLRequest(url: initialURL))
        }
    }

    static let probeScript = """
    (function() {
      function collect() {
        var out = [];
        function add(value) {
          if (typeof value === 'string' && value && value.indexOf('blob:') !== 0) {
            out.push(value);
          }
        }

        var sniffed = window.__videoExtractorSniffed || [];
        sniffed.forEach(add);

        document.querySelectorAll('video, audio, source, img').forEach(function(element) {
          add(element.currentSrc);
          add(element.src);
          add(element.getAttribute('data-src'));
        });

        document.querySelectorAll('iframe').forEach(function(element) {
          add(element.src);
        });

        try {
          performance.getEntriesByType('resource').forEach(function(entry) {
            var name = entry.name || '';
            if (/\\.(mp4|m3u8|mov|m4v|webm|mkv|mp3|m4a|jpg|jpeg|png|gif|webp|bmp|heic)(\\?|$)/i.test(name)) {
              add(name);
            }
          });
        } catch (error) {}

        return Array.from(new Set(out));
      }

      window.__videoExtractorProbe = collect;
      try {
        window.webkit.messageHandlers.mediaProbe.postMessage(JSON.stringify(collect()));
      } catch (error) {}
    })();
    """

    static let sniffScript = """
    (function() {
      var store = window.__videoExtractorSniffed = [];

      function push(value) {
        if (typeof value === 'string' && value && value.indexOf('blob:') !== 0) {
          store.push(value);
        }
      }

      var originalFetch = window.fetch;
      if (typeof originalFetch === 'function') {
        window.fetch = function() {
          try {
            var input = arguments[0];
            if (typeof input === 'string') {
              push(input);
            } else if (input && input.url) {
              push(input.url);
            } else if (input && input.href) {
              push(input.href);
            }
          } catch (error) {}
          return originalFetch.apply(this, arguments);
        };
      }

      var originalOpen = XMLHttpRequest.prototype.open;
      XMLHttpRequest.prototype.open = function(method, url) {
        try {
          push(String(url));
        } catch (error) {}
        return originalOpen.apply(this, arguments);
      };
    })();
    """

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        @Binding var discovered: [MediaCandidate]
        @Binding var pageURL: URL?
        @Binding var isLoading: Bool
        var lastProbeToken = 0

        init(
            discovered: Binding<[MediaCandidate]>,
            pageURL: Binding<URL?>,
            isLoading: Binding<Bool>,
            probeToken: Int
        ) {
            _discovered = discovered
            _pageURL = pageURL
            _isLoading = isLoading
            lastProbeToken = probeToken
        }

        func webView(
            _ webView: WKWebView,
            didStartProvisionalNavigation navigation: WKNavigation!
        ) {
            isLoading = true
        }

        func webView(
            _ webView: WKWebView,
            didFinish navigation: WKNavigation!
        ) {
            isLoading = false
            pageURL = webView.url
            scheduleProbe(in: webView)

            webView.evaluateJavaScript("document.documentElement.outerHTML") { [weak self] html, _ in
                guard let html = html as? String, let pageURL = webView.url else { return }
                let candidates = VideoExtractorEngine.extract(
                    fromText: html,
                    baseURL: pageURL,
                    pageURL: pageURL
                )
                DispatchQueue.main.async {
                    self?.merge(candidates)
                }
            }
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            isLoading = false
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            isLoading = false
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "mediaProbe" else { return }
            handleRawValues(message.body)
        }

        private func scheduleProbe(in webView: WKWebView) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                self.runProbe(webView)
            }
        }

        func runProbe(_ webView: WKWebView) {
            webView.evaluateJavaScript(
                "window.__videoExtractorProbe ? window.__videoExtractorProbe() : []"
            ) { [weak self] result, _ in
                guard let self else { return }
                DispatchQueue.main.async {
                    self.handleRawValues(result)
                }
            }
        }

        private func handleRawValues(_ raw: Any?) {
            var values: [String] = []

            if let array = raw as? [String] {
                values = array
            } else if let array = raw as? [Any] {
                values = array.compactMap { $0 as? String }
            } else if let string = raw as? String {
                if let data = string.data(using: .utf8),
                   let array = try? JSONSerialization.jsonObject(with: data) as? [String] {
                    values = array
                } else {
                    values = [string]
                }
            }

            let candidates = VideoExtractorEngine.candidates(
                from: values,
                baseURL: pageURL,
                pageURL: pageURL
            )
            merge(candidates)
        }

        private func merge(_ newCandidates: [MediaCandidate]) {
            var merged = discovered
            let existing = Set(merged.map(\.url.absoluteString))

            for candidate in newCandidates where !existing.contains(candidate.url.absoluteString) {
                merged.append(candidate)
            }

            discovered = merged
        }
    }
}
