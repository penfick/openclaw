import SwiftUI
import OpenClawKit

// Public ClawHub skill market. Mirrors Windows SkillsPage public tab + SkillHubClient.cs.
// Gateway `skills.search` (default keyword "tool", limit 40) with CLIENT-SIDE paging (12/page).
// Install via `skills.install {source:"clawhub", slug}` — ClawHub guarantees searchable ⇒ installable
// (unlike skills.sh /api/search which can surface un-installable entries).

struct PublicSkillItem: Identifiable, Hashable {
    let slug: String
    let name: String
    let summary: String
    let version: String
    let author: String

    var id: String { self.slug }
}

@MainActor
@Observable
final class PublicSkillsModel {
    var allItems: [PublicSkillItem] = []
    var keyword: String = ""
    var page: Int = 0
    var isLoading = false
    var installingSlug: String?
    var installedSlugs: Set<String> = []   // session-installed
    var error: String?
    var statusMessage: String?

    private let pageSize = 12
    private var didInitialSearch = false

    var visibleItems: [PublicSkillItem] {
        let start = self.page * self.pageSize
        let end = min(start + self.pageSize, self.allItems.count)
        guard start < end else { return [] }
        return Array(self.allItems[start..<end])
    }

    var totalPages: Int {
        max(1, (self.allItems.count + self.pageSize - 1) / self.pageSize)
    }

    func searchIfNeeded() async {
        guard !self.didInitialSearch else { return }
        self.didInitialSearch = true
        await self.search()
    }

    func search() async {
        self.isLoading = true
        self.error = nil
        self.page = 0
        let term = self.keyword.trimmingCharacters(in: .whitespaces)
        let effective = term.isEmpty ? "tool" : term
        do {
            let data = try await GatewayConnection.shared.request(
                method: "skills.search",
                params: ["query": AnyCodable(effective), "limit": AnyCodable(40)],
                timeoutMs: 20_000)
            self.allItems = Self.parseResults(data)
            self.statusMessage = self.allItems.isEmpty ? "无结果" : "找到 \(self.allItems.count) 个"
        } catch {
            self.error = "搜索失败：\(error.localizedDescription)"
            self.allItems = []
        }
        self.isLoading = false
    }

    func install(_ item: PublicSkillItem) async {
        guard self.installingSlug == nil else { return }
        self.installingSlug = item.slug
        do {
            _ = try await GatewayConnection.shared.request(
                method: "skills.install",
                params: ["source": AnyCodable("clawhub"), "slug": AnyCodable(item.slug)],
                timeoutMs: 60_000)
            self.installedSlugs.insert(item.slug)
            self.statusMessage = "已安装：\(item.name)"
            NotificationCenter.default.post(name: .openclawSkillsNeedRefresh, object: nil)
        } catch {
            self.error = "安装失败 [\(item.name)]：\(error.localizedDescription)"
        }
        self.installingSlug = nil
    }

    func nextPage() { if self.page < self.totalPages - 1 { self.page += 1 } }
    func prevPage() { if self.page > 0 { self.page -= 1 } }

    /// Tolerant parse: bare array, {results:[...]}, or {skills:[...]}.
    private static func parseResults(_ data: Data) -> [PublicSkillItem] {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return [] }
        let array: [[String: Any]]
        if let a = json as? [[String: Any]] {
            array = a
        } else if let dict = json as? [String: Any] {
            if let r = dict["results"] as? [[String: Any]] { array = r }
            else if let s = dict["skills"] as? [[String: Any]] { array = s }
            else { array = [] }
        } else {
            array = []
        }
        return array.compactMap { Self.parseItem($0) }
    }

    private static func parseItem(_ json: [String: Any]) -> PublicSkillItem? {
        let slug = (json["slug"] as? String) ?? (json["id"] as? String) ?? (json["name"] as? String) ?? ""
        guard !slug.isEmpty else { return nil }
        let name = (json["name"] as? String) ?? (json["displayName"] as? String) ?? slug
        let summary = (json["summary"] as? String) ?? (json["description"] as? String) ?? ""
        let version: String = {
            if let value = json["version"] as? String { return value }
            if let latest = json["latestVersion"] as? [String: Any], let value = latest["version"] as? String {
                return value
            }
            return ""
        }()
        let author: String = {
            if let value = json["author"] as? String { return value }
            if let owner = json["owner"] as? [String: Any] {
                return (owner["displayName"] as? String) ?? (owner["handle"] as? String) ?? ""
            }
            return ""
        }()
        return PublicSkillItem(slug: slug, name: name, summary: summary, version: version, author: author)
    }
}

struct PublicSkillsSection: View {
    @State private var model = PublicSkillsModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                TextField("搜索 ClawHub 技能（默认 tool）", text: self.$model.keyword)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await self.model.search() } }
                Button {
                    Task { await self.model.search() }
                } label: {
                    if self.model.isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("搜索", systemImage: "magnifyingglass")
                    }
                }
                .buttonStyle(.bordered)
            }

            if let error = self.model.error {
                Text(error).font(.footnote).foregroundStyle(.orange)
            } else if let status = self.model.statusMessage {
                Text(status).font(.footnote).foregroundStyle(.secondary)
            }

            if self.model.allItems.isEmpty && !self.model.isLoading {
                Text("暂无结果").font(.callout).foregroundStyle(.secondary)
            } else {
                let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    ForEach(self.model.visibleItems) { item in
                        self.card(item)
                    }
                }
                HStack {
                    Button("上一页") { self.model.prevPage() }
                        .disabled(self.model.page == 0)
                    Text("第 \(self.model.page + 1) / \(self.model.totalPages) 页")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("下一页") { self.model.nextPage() }
                        .disabled(self.model.page >= self.model.totalPages - 1)
                    Spacer()
                }
            }
        }
        .task { await self.model.searchIfNeeded() }
    }

    private func card(_ item: PublicSkillItem) -> some View {
        let installed = self.model.installedSlugs.contains(item.slug)
        let installing = self.model.installingSlug == item.slug
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(item.name).font(.callout.weight(.semibold)).lineLimit(1)
                if !item.version.isEmpty {
                    Text("v\(item.version)").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
            }
            if !item.summary.isEmpty {
                Text(item.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            if !item.author.isEmpty {
                Text(item.author).font(.caption2).foregroundStyle(.tertiary)
            }
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
}
