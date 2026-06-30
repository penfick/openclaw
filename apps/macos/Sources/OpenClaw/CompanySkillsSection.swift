import SwiftUI

// Company Skills Hub market tab. Mirrors Windows CompanySkillsPage.xaml.cs.
// Gated on OA login; searches the company REST hub; install routes through SkillInstaller
// (downloads zip + uploads to gateway). On install success, posts .openclawSkillsNeedRefresh so
// the "installed" tab re-reads skills.status.

extension Notification.Name {
    static let openclawSkillsNeedRefresh = Notification.Name("openclaw.skillsNeedRefresh")
}

@MainActor
@Observable
final class CompanySkillsModel {
    var items: [CompanySkillItem] = []
    var installedIds: Set<Int> = []
    var installingId: Int?
    var keyword: String = ""
    var isLoading = false
    var statusMessage: String?
    var error: String?

    func refresh() async {
        self.isLoading = true
        self.error = nil
        do {
            let result = try await CompanySkillsHub.search(keyword: self.keyword)
            self.items = result.items
            self.statusMessage = result.total > 0 ? "共 \(result.total) 个结果" : "无结果"
        } catch {
            self.error = error.localizedDescription
            self.items = []
        }
        self.isLoading = false
    }

    func install(_ item: CompanySkillItem) async {
        guard self.installingId == nil else { return }
        self.installingId = item.id
        self.statusMessage = "正在安装 \(item.name)…"
        do {
            try await SkillInstaller.install(skillId: item.id, slug: item.slug)
            self.installedIds.insert(item.id)
            self.statusMessage = "已安装：\(item.name)"
            NotificationCenter.default.post(name: .openclawSkillsNeedRefresh, object: nil)
        } catch {
            self.error = "安装失败 [\(item.name)]：\(error.localizedDescription)"
        }
        self.installingId = nil
    }
}

struct CompanySkillsSection: View {
    @State private var model = CompanySkillsModel()
    @State private var didAutoBrowse = false

    private var auth: OAAuthCoordinator { OAAuthCoordinator.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !self.auth.authenticated {
                self.loginGate
            } else {
                self.searchBar
                if let error = self.model.error {
                    Text(error).font(.footnote).foregroundStyle(.orange)
                } else if let status = self.model.statusMessage {
                    Text(status).font(.footnote).foregroundStyle(.secondary)
                }
                self.cardsList
            }
        }
        .task { await self.maybeBrowse() }
        .onChange(of: self.auth.authenticated) { _, _ in
            Task { await self.maybeBrowse() }
        }
    }

    private func maybeBrowse() async {
        guard self.auth.authenticated, !self.didAutoBrowse else { return }
        self.didAutoBrowse = true
        await self.model.refresh()
    }

    private var loginGate: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "lock.fill").foregroundStyle(.secondary)
            Text("请先在「Account」页登录 OA 账号").font(.callout)
            Text("公司技能市场需要 OA 身份验证。").font(.footnote).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.38), in: RoundedRectangle(cornerRadius: 12))
    }

    private var searchBar: some View {
        HStack {
            TextField("搜索公司技能", text: self.$model.keyword)
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await self.model.refresh() } }
            Button {
                Task { await self.model.refresh() }
            } label: {
                if self.model.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Label("搜索", systemImage: "magnifyingglass")
                }
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var cardsList: some View {
        if self.model.items.isEmpty && !self.model.isLoading {
            Text("暂无技能").font(.callout).foregroundStyle(.secondary)
        } else {
            let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(self.model.items) { item in
                    self.card(item)
                }
            }
        }
    }

    private func card(_ item: CompanySkillItem) -> some View {
        let installed = self.model.installedIds.contains(item.id)
        let installing = self.model.installingId == item.id
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(item.name).font(.callout.weight(.semibold))
                if let version = item.version, !version.isEmpty {
                    Text("v\(version)").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
            }
            if let desc = item.description, !desc.isEmpty {
                Text(desc).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Text(Self.metaLine(item)).font(.caption2).foregroundStyle(.tertiary)
            HStack {
                Spacer()
                if installing {
                    Text("正在安装…").font(.caption).foregroundStyle(.secondary)
                } else if installed {
                    Text("已安装").font(.caption).foregroundStyle(.green)
                } else {
                    Button("安装") { Task { await self.model.install(item) } }
                        .buttonStyle(.bordered).controlSize(.small)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.38), in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.055)) }
    }

    private static func metaLine(_ item: CompanySkillItem) -> String {
        var parts: [String] = []
        if let author = item.authorName, !author.isEmpty { parts.append(author) }
        if let dept = item.deptName, !dept.isEmpty { parts.append(dept) }
        if item.downloadCount > 0 { parts.append("下载 \(item.downloadCount)") }
        return parts.joined(separator: " · ")
    }
}
