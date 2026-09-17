import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct DownloadsView: View {
    @State private var files: [URL] = []
    @ObservedObject private var directoryStore = DownloadDirectoryStore.shared
    @State private var showFolderPicker = false
    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 14)
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                directoryBar
                Divider()

                Group {
                    if files.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 46))
                                .foregroundStyle(.secondary)

                            Text("暂无下载")
                                .font(.headline)

                            Text("从解析结果中下载的视频会显示在这里。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(files, id: \.self) { file in
                                NavigationLink {
                                    MediaPlayerView(fileURL: file)
                                } label: {
                                    fileCard(file)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    ShareLink(item: file)

                                    Button(role: .destructive) {
                                        delete(file)
                                    } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                }
                            }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 16)
                        }
                    }
                }
            }
            .navigationTitle("下载")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showFolderPicker = true
                    } label: {
                        Label("目录", systemImage: "folder")
                    }
                }
            }
            .onAppear(perform: reload)
            .refreshable { reload() }
            .fileImporter(
                isPresented: $showFolderPicker,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        directoryStore.set(url)
                        reload()
                    }
                case .failure:
                    break
                }
            }
        }
    }

    private var directoryBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.fill")
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text("保存位置")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(directoryStore.displayName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
            }

            Spacer()

            if directoryStore.isCustomDirectory {
                Button("恢复默认") {
                    directoryStore.reset()
                    reload()
                }
                .font(.caption)
            } else {
                Button("打开本地文件夹") {
                    openLocalDownloadsFolder()
                }
                .font(.caption)
            }

            Button {
                showFolderPicker = true
            } label: {
                Label(
                    directoryStore.isCustomDirectory ? "更改" : "选择目录",
                    systemImage: "folder.badge.plus"
                )
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .liquidGlassCard(cornerRadius: 20, shadowRadius: 10)
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private func reload() {
        files = MediaDownloader.savedFiles()
    }

    private func delete(_ url: URL) {
        MediaDownloader.delete(url)
        reload()
    }

    private func fileSize(_ url: URL) -> String {
        guard let attributes = try? FileManager.default.attributesOfItem(
            atPath: url.path
        ) else {
            return ""
        }

        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    private func openLocalDownloadsFolder() {
        let documents = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first
        let downloads = documents?.appendingPathComponent(
            "Downloads",
            isDirectory: true
        )
        let path = downloads?.path ?? ""
        let encoded = path.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ) ?? path

        guard let url = URL(string: "shareddocuments://\(encoded)") else {
            return
        }
        UIApplication.shared.open(url)
    }

    private func fileCard(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: fileIconName(url))
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(fileIconColor(url))
                .frame(width: 52, height: 52)
                .background(
                    fileIconColor(url).opacity(0.14),
                    in: RoundedRectangle(cornerRadius: 15)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(url.lastPathComponent)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)

                Text(fileSize(url))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 138, alignment: .topLeading)
        .padding(16)
        .liquidGlassCard(cornerRadius: 22, shadowRadius: 12)
    }

    private func fileIconName(_ url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "gif", "webp", "bmp", "heic":
            return "photo.fill"
        case "mp4", "mov", "m4v", "webm", "mkv", "m3u8":
            return "film.fill"
        case "mp3", "m4a":
            return "music.note"
        default:
            return "doc.fill"
        }
    }

    private func fileIconColor(_ url: URL) -> Color {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "gif", "webp", "bmp", "heic":
            return .pink
        case "mp4", "mov", "m4v", "webm", "mkv", "m3u8":
            return .blue
        case "mp3", "m4a":
            return .purple
        default:
            return .gray
        }
    }
}
