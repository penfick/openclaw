import Foundation
import OpenClawKit

// Install a company-market skill zip into the gateway. Mirrors Windows CompanySkillInstaller.cs.
// Steps: best-effort direct-file allowUploadedArchives=true → skills.upload.begin →
// chunked upload (512KB base64, byte offset) → skills.upload.commit →
// skills.install {source:"upload"} (gateway extracts server-side).
// All RPC via GatewayConnection.request(method: String) (these methods aren't in the Method enum).
// @MainActor: calls EnterpriseConfigPatch (@MainActor) + CompanySkillsHub (@MainActor).

@MainActor
enum SkillInstaller {
    private static let chunkSize = 512 * 1024

    /// Download `skillId` from the company hub and install it into the gateway.
    static func install(skillId: Int, slug: String) async throws {
        // Step 0: best-effort enable uploaded-archive installs (idempotent; ignore failure).
        try? await Self.enableAllowUploadedArchives()

        // Download zip from company hub.
        let zip = try await CompanySkillsHub.downloadZip(skillId: skillId)

        // Step 1: begin.
        let beginParams: [String: AnyCodable] = [
            "kind": AnyCodable("skill-archive"),
            "slug": AnyCodable(slug),
            "sizeBytes": AnyCodable(zip.count),
        ]
        let beginData = try await GatewayConnection.shared.request(
            method: "skills.upload.begin", params: beginParams, timeoutMs: 30_000)
        guard let uploadId = Self.parseString(beginData, key: "uploadId"), !uploadId.isEmpty else {
            throw Self.error("网关未返回 uploadId，skills.upload.begin 失败。")
        }

        // Step 2: chunked upload (512KB, base64, byte offset).
        var offset = 0
        while offset < zip.count {
            let end = min(offset + Self.chunkSize, zip.count)
            let chunk = zip.subdata(in: offset..<end)
            let chunkParams: [String: AnyCodable] = [
                "uploadId": AnyCodable(uploadId),
                "offset": AnyCodable(offset),
                "dataBase64": AnyCodable(chunk.base64EncodedString()),
            ]
            _ = try await GatewayConnection.shared.request(
                method: "skills.upload.chunk", params: chunkParams, timeoutMs: 60_000)
            offset = end
        }

        // Step 3: commit.
        _ = try await GatewayConnection.shared.request(
            method: "skills.upload.commit",
            params: ["uploadId": AnyCodable(uploadId)],
            timeoutMs: 30_000)

        // Step 4: install (gateway extracts server-side).
        let installParams: [String: AnyCodable] = [
            "source": AnyCodable("upload"),
            "uploadId": AnyCodable(uploadId),
            "slug": AnyCodable(slug),
        ]
        _ = try await GatewayConnection.shared.request(
            method: "skills.install", params: installParams, timeoutMs: 60_000)
    }

    private static func enableAllowUploadedArchives() async throws {
        let patch = EnterpriseConfigPatch.buildNestedPatch(
            parentPath: EnterpriseConfigPaths.skillsInstall,
            finalKey: "allowUploadedArchives",
            value: true)
        try await EnterpriseConfigPatch.writePatch(patch)
    }

    private static func parseString(_ data: Data, key: String) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json[key] as? String
    }

    private static func error(_ message: String) -> NSError {
        NSError(domain: "SkillInstaller", code: 0, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
