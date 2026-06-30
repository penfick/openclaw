import Foundation

// Company Skills Hub REST client. Mirrors Windows CompanySkillsHubClient.cs.
// All requests carry the OA Bearer token (from OAAuthCoordinator.validAccessToken).
// Base URL default http://localhost:3000 (OASettings.companySkillsHubUrl).

struct CompanySkillItem: Identifiable, Hashable, Codable {
    let id: Int
    let slug: String
    let name: String
    let description: String?
    let version: String?
    let categoryId: Int?
    let authorId: String?
    let authorName: String?
    let deptId: Int?
    let deptName: String?
    let downloadCount: Int
    let status: Int
    let createdAt: String?
    let updatedAt: String?
}

struct CompanySkillSearchResult {
    let success: Bool
    let items: [CompanySkillItem]
    let total: Int
    let page: Int
    let pageSize: Int
}

struct CompanySkillUploadMeta {
    let slug: String
    let name: String
    let description: String?
    let version: String?
    let categoryId: Int?   // hard-coded nil in this phase (no category picker)
    let authorId: String?
    let authorName: String?
    let deptId: Int?
    let deptName: String?
}

@MainActor
enum CompanySkillsHub {
    private static var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        return URLSession(configuration: config)
    }()

    private static var baseUrl: String { EnvConfig.companySkillsHubUrl }

    // MARK: - Search

    static func search(keyword: String?) async throws -> CompanySkillSearchResult {
        let token = try await Self.requireToken()
        var query = "page=1&pageSize=20"
        if let keyword, !keyword.isEmpty {
            query = "keyword=\(Self.encode(keyword))&" + query
        }
        guard let url = URL(string: "\(Self.baseUrl)/api/skills?\(query)") else {
            throw Self.error("公司市场 URL 无效")
        }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await Self.session.data(for: req)
        try Self.ensureOk(resp, data: data, label: "搜索")
        return Self.parseSearch(data)
    }

    // MARK: - Download

    static func downloadZip(skillId: Int) async throws -> Data {
        let token = try await Self.requireToken()
        guard let url = URL(string: "\(Self.baseUrl)/api/skills/\(skillId)/download") else {
            throw Self.error("下载 URL 无效")
        }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await Self.session.data(for: req)
        try Self.ensureOk(resp, data: data, label: "下载")
        return data
    }

    // MARK: - Upload (multipart)

    /// Returns the new skill id (0 if the response lacks one).
    static func upload(zipData: Data, meta: CompanySkillUploadMeta) async throws -> Int {
        let token = try await Self.requireToken()
        let boundary = "----OpenClawBoundary\(UUID().uuidString)"
        guard let url = URL(string: "\(Self.baseUrl)/api/skills") else {
            throw Self.error("上传 URL 无效")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = Self.buildMultipart(boundary: boundary, zipData: zipData, meta: meta)
        let (data, resp) = try await Self.session.data(for: req)
        try Self.ensureOk(resp, data: data, label: "上传")
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let id = json["id"] as? Int
        {
            return id
        }
        return 0
    }

    // MARK: - Helpers

    private static func requireToken() async throws -> String {
        guard let token = await OAAuthCoordinator.shared.validAccessToken(), !token.isEmpty else {
            throw Self.error("未登录 OA 账号，请先在「Account」页登录。")
        }
        return token
    }

    private static func ensureOk(_ resp: URLResponse, data: Data, label: String) throws {
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8) ?? ""
            throw Self.error("\(label)失败 (\(code)): \(body)")
        }
    }

    private static func error(_ message: String) -> NSError {
        NSError(domain: "CompanySkillsHub", code: 0, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private static func encode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
    }

    private static func parseSearch(_ data: Data) -> CompanySkillSearchResult {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return CompanySkillSearchResult(success: false, items: [], total: 0, page: 1, pageSize: 20)
        }
        var items: [CompanySkillItem] = []
        if let arr = json["data"] as? [[String: Any]] {
            for element in arr {
                if let item = Self.parseItem(element) { items.append(item) }
            }
        }
        return CompanySkillSearchResult(
            success: json["success"] as? Bool ?? false,
            items: items,
            total: json["total"] as? Int ?? 0,
            page: json["page"] as? Int ?? 1,
            pageSize: json["pageSize"] as? Int ?? 20)
    }

    private static func parseItem(_ json: [String: Any]) -> CompanySkillItem? {
        guard let id = json["id"] as? Int,
              let slug = json["slug"] as? String,
              let name = json["name"] as? String
        else { return nil }
        return CompanySkillItem(
            id: id, slug: slug, name: name,
            description: json["description"] as? String,
            version: json["version"] as? String,
            categoryId: json["categoryId"] as? Int,
            authorId: json["authorId"] as? String,
            authorName: json["authorName"] as? String,
            deptId: json["deptId"] as? Int,
            deptName: json["deptName"] as? String,
            downloadCount: json["downloadCount"] as? Int ?? 0,
            status: json["status"] as? Int ?? 0,
            createdAt: json["createdAt"] as? String,
            updatedAt: json["updatedAt"] as? String)
    }

    /// Build a multipart/form-data body. file=`{slug}.zip` (required), slug/name required,
    /// optional fields appended only when non-empty (categoryId/deptId use HasValue semantics:
    /// sent whenever non-nil, including 0).
    private static func buildMultipart(boundary: String, zipData: Data, meta: CompanySkillUploadMeta) -> Data {
        var body = Data()
        let crlf = "\r\n"

        func append(_ b: inout Data, _ bytes: Data) { b.append(bytes) }
        func appendString(_ b: inout Data, _ s: String) { b.append(s.data(using: .utf8) ?? Data()) }
        func appendField(_ b: inout Data, _ name: String, _ value: String) {
            appendString(&b, "--\(boundary)\(crlf)")
            appendString(&b, "Content-Disposition: form-data; name=\"\(name)\"\(crlf)\(crlf)")
            appendString(&b, "\(value)\(crlf)")
        }

        // file part
        appendString(&body, "--\(boundary)\(crlf)")
        appendString(&body, "Content-Disposition: form-data; name=\"file\"; filename=\"\(meta.slug).zip\"\(crlf)")
        appendString(&body, "Content-Type: application/zip\(crlf)\(crlf)")
        append(&body, zipData)
        appendString(&body, crlf)

        // required
        appendField(&body, "slug", meta.slug)
        appendField(&body, "name", meta.name)
        // optional (non-empty only)
        if let desc = meta.description, !desc.isEmpty { appendField(&body, "description", desc) }
        if let version = meta.version, !version.isEmpty { appendField(&body, "version", version) }
        if let categoryId = meta.categoryId { appendField(&body, "categoryId", "\(categoryId)") }
        if let authorId = meta.authorId, !authorId.isEmpty { appendField(&body, "authorId", authorId) }
        if let authorName = meta.authorName, !authorName.isEmpty { appendField(&body, "authorName", authorName) }
        if let deptId = meta.deptId { appendField(&body, "deptId", "\(deptId)") }
        if let deptName = meta.deptName, !deptName.isEmpty { appendField(&body, "deptName", deptName) }

        appendString(&body, "--\(boundary)--\(crlf)")
        return body
    }
}
