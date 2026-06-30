import SwiftUI

// Upload-to-company-market sheet. Mirrors Windows UploadSkillDialog.xaml.cs.
// Pre-filled from an installed skill (name/slug/desc/baseDir). OA UserInfo → author attribution.
// Flow: validate → SkillPackager.pack(baseDir) → CompanySkillsHub.upload(multipart).

struct UploadSkillSheet: View {
    let baseDir: String
    @Binding var isUploading: Bool
    @Binding var error: String?
    let onCancel: () -> Void
    let onComplete: (Bool) -> Void

    @State private var slugText: String
    @State private var nameText: String
    @State private var descText: String
    @State private var versionText: String = "1.0.0"
    @State private var statusText: String = ""

    init(
        name: String,
        slug: String,
        description: String,
        baseDir: String,
        isUploading: Binding<Bool>,
        error: Binding<String?>,
        onCancel: @escaping () -> Void,
        onComplete: @escaping (Bool) -> Void)
    {
        self.baseDir = baseDir
        self._isUploading = isUploading
        self._error = error
        self.onCancel = onCancel
        self.onComplete = onComplete
        self._slugText = State(initialValue: slug.isEmpty ? name : slug)
        self._nameText = State(initialValue: name)
        self._descText = State(initialValue: description)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("上传到公司市场").font(.headline)

            self.field("Slug", self.$slugText, "英文唯一标识")
            self.field("名称", self.$nameText, "")

            VStack(alignment: .leading, spacing: 6) {
                Text("描述").font(.callout)
                TextEditor(text: self.$descText)
                    .font(.callout)
                    .frame(minHeight: 60, maxHeight: 100)
                    .padding(4)
                    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
            }

            self.field("版本", self.$versionText, "1.0.0")

            if !self.statusText.isEmpty {
                Text(self.statusText).font(.footnote).foregroundStyle(.secondary)
            }
            if let error = self.error {
                Text(error).font(.footnote).foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button("取消", role: .cancel) { self.onCancel() }
                Button("上传") { Task { await self.performUpload() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(self.isUploading)
            }
        }
        .padding(20)
    }

    private func field(_ title: String, _ text: Binding<String>, _ placeholder: String) -> some View {
        HStack(alignment: .center) {
            Text(title).font(.callout).frame(width: 64, alignment: .leading)
            TextField(placeholder, text: text).textFieldStyle(.roundedBorder)
        }
    }

    @MainActor
    private func performUpload() async {
        self.error = nil
        let slug = self.slugText.trimmingCharacters(in: .whitespaces)
        let name = self.nameText.trimmingCharacters(in: .whitespaces)
        guard !slug.isEmpty, !name.isEmpty else {
            self.error = "Slug 和名称不能为空。"
            return
        }

        self.isUploading = true
        self.statusText = "正在打包技能目录…"
        do {
            let zip = try await SkillPackager.pack(baseDir: self.baseDir)
            self.statusText = "正在上传（\(zip.count / 1024) KB）…"

            let user = OAAuthCoordinator.shared.userInfo
            let meta = CompanySkillUploadMeta(
                slug: slug,
                name: name,
                description: self.descText.trimmingCharacters(in: .whitespaces).isEmpty
                    ? nil : self.descText.trimmingCharacters(in: .whitespaces),
                version: self.versionText.trimmingCharacters(in: .whitespaces).isEmpty
                    ? nil : self.versionText.trimmingCharacters(in: .whitespaces),
                categoryId: nil,
                authorId: user?.userId,
                authorName: user?.displayName,
                deptId: user?.departmentId.flatMap { Int($0) },
                deptName: user?.departmentName)

            _ = try await CompanySkillsHub.upload(zipData: zip, meta: meta)
            self.isUploading = false
            self.onComplete(true)
        } catch {
            self.isUploading = false
            self.error = error.localizedDescription
        }
    }
}
