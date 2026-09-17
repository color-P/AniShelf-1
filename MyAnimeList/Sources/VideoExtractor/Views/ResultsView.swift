import SwiftUI
import UIKit

struct ResultsView: View {
    @Binding var candidates: [MediaCandidate]
    let pageURL: URL?

    @State private var statuses: [UUID: String] = [:]
    @ObservedObject private var downloadManager = DownloadManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(candidates) { candidate in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        Image(
                            systemName: candidate.kind.isImage
                                ? "photo"
                                : (candidate.kind.isVideo ? "film" : "music.note")
                        )
                            .foregroundStyle(.tint)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(candidate.displayTitle)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(2)

                            Text(candidate.kind.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if let quality = candidate.quality, !quality.isEmpty {
                                Text(quality)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Text(candidate.url.absoluteString)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(2)
                        }
                    }

                    HStack(spacing: 8) {
                        NavigationLink {
                            MediaPlayerView(candidate: candidate)
                        } label: {
                            Label("预览", systemImage: "play")
                                .font(.footnote)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(LiquidGlassButtonStyle())

                        Button {
                            copy(candidate)
                        } label: {
                            Label("复制", systemImage: "doc.on.doc")
                                .font(.footnote)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(LiquidGlassButtonStyle())

                        if candidate.kind != .m3u8 {
                            Button {
                                Task { await download(candidate) }
                            } label: {
                                if downloadManager.isDownloading(candidate) {
                                    ProgressView()
                                        .frame(maxWidth: .infinity)
                                } else {
                                    Label("下载", systemImage: "arrow.down.circle")
                                        .font(.footnote)
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .buttonStyle(LiquidGlassButtonStyle())
                        }
                    }

                    if downloadManager.isDownloading(candidate) {
                        VStack(alignment: .leading, spacing: 4) {
                            ProgressView(value: downloadManager.progress(for: candidate))
                                .progressViewStyle(.linear)

                            Text(downloadManager.status(for: candidate) ?? "下载中...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let status = statuses[candidate.id] {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .liquidGlassCard(cornerRadius: 22, shadowRadius: 10)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .overlay {
            if candidates.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "video.slash")
                        .font(.system(size: 42))
                        .foregroundStyle(.secondary)

                    Text("还没有提取到媒体地址")
                        .font(.headline)

                    Text("回到“浏览器”页面，播放视频后再点右上角“提取”。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }
            }
        }
        .navigationTitle("解析结果")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") {
                    dismiss()
                }
            }
        }
    }

    private func isDownloading(_ candidate: MediaCandidate) -> Bool {
        downloadManager.isDownloading(candidate)
    }

    private func copy(_ candidate: MediaCandidate) {
        UIPasteboard.general.string = candidate.url.absoluteString
        statuses[candidate.id] = "链接已复制"
    }

    @MainActor
    private func download(_ candidate: MediaCandidate) async {
        do {
            _ = try await downloadManager.download(candidate)
            statuses[candidate.id] = "已保存，可到“下载”页查看"
        } catch {
            statuses[candidate.id] = "下载失败：\(error.localizedDescription)"
        }
    }
}

private struct LiquidGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.footnote)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .foregroundStyle(.primary)
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.white.opacity(0.28), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: configuration.isPressed)
    }
}
