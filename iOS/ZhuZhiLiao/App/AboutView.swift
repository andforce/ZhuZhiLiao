import SwiftUI

enum AppLinks {
    static let website = URL(string: "https://andforce.github.io/ZhuZhiLiao/")!
    static let support = URL(string: "https://andforce.github.io/ZhuZhiLiao/support/")!
    static let privacyPolicy = URL(string: "https://andforce.github.io/ZhuZhiLiao/privacy/")!
    static let privacyChoices = URL(string: "https://andforce.github.io/ZhuZhiLiao/privacy/#data-control")!
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                appIdentity
                supportAndPrivacy
                dataPractices
                dataControl
                copyright
            }
            .listStyle(.insetGrouped)
            .navigationTitle("关于")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成", action: dismiss.callAsFunction)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(30)
    }

    private var appIdentity: some View {
        Section {
            VStack(spacing: 10) {
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 52, weight: .medium))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.orange, .brown)
                    .accessibilityHidden(true)

                Text("赛博竹知了")
                    .font(.title2.weight(.bold))

                Text("版本 \(appVersion)（\(buildNumber)）")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("版本 \(appVersion)，构建 \(buildNumber)")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
    }

    private var supportAndPrivacy: some View {
        Section("支持与隐私") {
            ExternalLinkRow(
                title: "隐私政策",
                systemImage: "hand.raised.fill",
                destination: AppLinks.privacyPolicy
            )
            .accessibilityHint("在浏览器中打开完整隐私政策")

            ExternalLinkRow(
                title: "联系支持",
                systemImage: "envelope.fill",
                destination: AppLinks.support
            )
            .accessibilityHint("在浏览器中打开支持页面和联系邮箱")

            ExternalLinkRow(
                title: "官方网站",
                systemImage: "globe",
                destination: AppLinks.website
            )
        }
    }

    private var dataPractices: some View {
        Section("数据与权限") {
            Label("无账号、无广告、无第三方分析 SDK", systemImage: "checkmark.shield.fill")
            Label("动作传感器原始数据仅在本机处理", systemImage: "gyroscope")
            Label("位置仅在主动加入哇声地球后请求", systemImage: "location.fill")
        }
    }

    private var dataControl: some View {
        Section("数据控制") {
            Text("可在哇声地球中随时退出并删除粗略格网位置；可在排行榜中使用“清除我的匿名数据”删除匿名身份、排名和相关数据。")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ExternalLinkRow(
                title: "查看删除与撤回说明",
                systemImage: "person.crop.circle.badge.minus",
                destination: AppLinks.privacyChoices
            )
        }
    }

    private var copyright: some View {
        Section {
            Text("© 2026 王迪远")
                .frame(maxWidth: .infinity, alignment: .center)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .listRowBackground(Color.clear)
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }
}

private struct ExternalLinkRow: View {
    let title: String
    let systemImage: String
    let destination: URL

    var body: some View {
        Link(destination: destination) {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview("关于") {
    Color.black
        .sheet(isPresented: .constant(true)) {
            AboutView()
        }
}
