import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selectedTab) {
                HomeView(selectedTab: $selectedTab)
                    .tag(0)

                BrowserExtractorView()
                    .tag(1)

                DownloadsView()
                    .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            sectionPicker
        }
        .background {
            ZStack {
                Color(.systemGroupedBackground)

                Circle()
                    .fill(.indigo.opacity(0.28))
                    .frame(width: 280, height: 280)
                    .blur(radius: 80)
                    .offset(x: -130, y: -260)

                Circle()
                    .fill(.pink.opacity(0.22))
                    .frame(width: 320, height: 320)
                    .blur(radius: 90)
                    .offset(x: 150, y: 250)

                Circle()
                    .fill(.teal.opacity(0.20))
                    .frame(width: 240, height: 240)
                    .blur(radius: 85)
                    .offset(x: 100, y: -140)
            }
            .ignoresSafeArea()
        }
    }

    private var sectionPicker: some View {
        Picker("功能", selection: $selectedTab) {
            Label("解析", systemImage: "magnifyingglass")
                .tag(0)
            Label("浏览器", systemImage: "safari")
                .tag(1)
            Label("下载", systemImage: "folder")
                .tag(2)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.42), .white.opacity(0.10)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .shadow(color: .black.opacity(0.10), radius: 12, x: 0, y: 6)
    }
}

struct LiquidGlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat
    var shadowRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.42), .white.opacity(0.10)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(
                color: .black.opacity(0.14),
                radius: shadowRadius,
                x: 0,
                y: 8
            )
    }
}

extension View {
    func liquidGlassCard(
        cornerRadius: CGFloat = 24,
        shadowRadius: CGFloat = 14
    ) -> some View {
        modifier(
            LiquidGlassCardModifier(
                cornerRadius: cornerRadius,
                shadowRadius: shadowRadius
            )
        )
    }
}
