import Foundation

// Pack a local skill directory into a zip. Replaces Windows wsl.exe+python3 (Mac has no WSL;
// the gateway baseDir is a native path). Uses the system /usr/bin/zip via ShellExecutor,
// mirroring the python script spec: recursive, relative entries, deflate, files only.
// `-X` strips extended attributes (.DS_Store / xattr noise).

enum SkillPackager {
    /// Pack `baseDir` into an in-memory zip `Data`.
    static func pack(baseDir: String) async throws -> Data {
        let trimmed = baseDir.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            throw Self.error("该技能无本地目录，无法上传。")
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: trimmed, isDirectory: &isDir), isDir.boolValue else {
            throw Self.error("技能目录不存在：\(trimmed)")
        }

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("openclaw-skill-\(UUID().uuidString).zip")
        // zip -r -X <archive> .   run inside baseDir so entries are relative to it.
        let result = await ShellExecutor.runDetailed(
            command: ["/usr/bin/zip", "-r", "-X", tmp.path, "."],
            cwd: trimmed,
            env: nil,
            timeout: 30)

        guard result.success, FileManager.default.fileExists(atPath: tmp.path) else {
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = stderr.isEmpty ? (result.errorMessage ?? "zip 失败") : stderr
            throw Self.error("打包失败：\(detail)")
        }
        defer { try? FileManager.default.removeItem(at: tmp) }
        return try Data(contentsOf: tmp)
    }

    private static func error(_ message: String) -> NSError {
        NSError(domain: "SkillPackager", code: 0, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
