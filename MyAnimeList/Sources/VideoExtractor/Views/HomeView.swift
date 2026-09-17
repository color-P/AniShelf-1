import SwiftUI
import UIKit

struct HomeView: View {
    @Binding var selectedTab: Int

    @State private var urlText = ""
    @State private var isLoading = false
    @State private var candidates: [MediaCandidate] = []
    @State private var pageURL: URL?
    @State private var errorMessage: String?
    @State private var showResults = false
    @FocusState private var inputFocused: Bool

    private let engine = VideoExtractorEngine()
    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 14)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    heroCard
                    quickActions
                    capabilityNote
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(Color.clear)
            .navigationTitle("视频提取")
            .sheet(isPresented: $showResults) {
                NavigationStack {
                    ResultsView(candidates: $candidates, pageURL: pageURL)
                }
            }
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("粘贴链接，提取视频", systemImage: "link")
                .font(.headline)

            HStack(spacing: 10) {
                TextField("https://example.com/video", text: $urlText)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .focused($inputFocused)
                    .submitLabel(.go)
                    .onSubmit {
                        Task { await extract() }
                    }

                if !urlText.isEmpty {
                    Button {
                        urlText = ""
                        errorMessage = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    Task { await extract() }
                } label: {
                    if isLoading {
                        ProgressView()
                            .frame(width: 18, height: 18)
                    } else {
                        Text("提取")
                            .fontWeight(.semibold)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(urlText.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding(18)
        .liquidGlassCard(cornerRadius: 26, shadowRadius: 16)
    }

    private var quickActions: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
            actionCard(
                title: "浏览器提取",
                subtitle: "打开页面并自动收集媒体",
                systemImage: "safari.fill",
                color: .blue
            ) {
                selectedTab = 1
            }

            actionCard(
                title: "下载管理",
                subtitle: "查看、分享、选择保存目录",
                systemImage: "folder.fill",
                color: .purple
            ) {
                selectedTab = 2
            }

            actionCard(
                title: "X / Twitter",
                subtitle: "解析公开推文视频",
                systemImage: "bird.fill",
                color: .teal
            ) {
                urlText = "https://x.com/"
                inputFocused = true
            }
        }
    }

    private func actionCard(
        title: String,
        subtitle: String,
        systemImage: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 46, height: 46)
                    .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .padding(16)
            .liquidGlassCard(cornerRadius: 22, shadowRadius: 12)
        }
        .buttonStyle(.plain)
    }

    private var capabilityNote: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("支持范围", systemImage: "checkmark.shield.fill")
                .font(.headline)

            Text("可识别公开网页中的 MP4、HLS、MOV、WebM、图片等媒体地址。\n遇到动态加载页面时，请使用“浏览器提取”，播放视频后再点提取。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .liquidGlassCard(cornerRadius: 22, shadowRadius: 12)
    }

    @MainActor
    private func extract() async {
        inputFocused = false
        errorMessage = nil

        guard let url = VideoExtractorEngine.normalizedURL(from: urlText) else {
            errorMessage = VideoExtractorError.invalidURL.localizedDescription
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            candidates = try await engine.extract(from: url)
            pageURL = url
            showResults = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
