import SwiftUI

// OA (corporate) account page. Mirrors Windows AccountPage.xaml.cs.
// Login opens the browser to the OA authorize URL; the tclaw:// callback completes login
// asynchronously, then @Observable OAAuthCoordinator flips `authenticated` and this view
// re-renders automatically.

struct AccountSettings: View {
    @State private var isLoggingOut = false

    private var auth: OAAuthCoordinator { OAAuthCoordinator.shared }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 20) {
                SettingsPageHeader(
                    title: "OA 账号",
                    subtitle: "登录 OA 账号以使用公司技能市场等内部功能。此账号与网关设备配对相互独立。")

                if let error = self.auth.lastError, !self.auth.authenticated {
                    Text(error).font(.footnote).foregroundStyle(.orange)
                }

                if self.auth.authenticated, let user = self.auth.userInfo {
                    self.loggedInCard(user)
                } else {
                    self.loggedOutCard
                }
                Spacer(minLength: 8)
            }
            .settingsDetailContent()
        }
    }

    private var loggedOutCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.system(size: 30))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("未登录").font(.headline)
                    Text("登录后可访问公司技能市场，并作为上传技能的作者身份归属。")
                        .font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            Text("点击登录后，请在弹出的浏览器中完成授权。")
                .font(.footnote).foregroundStyle(.secondary)
            Button {
                _ = OAAuthCoordinator.shared.startLogin()
            } label: {
                Label("登录", systemImage: "arrow.right.square")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.38), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.055)) }
    }

    private func loggedInCard(_ user: OaUserInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsCardGroup("账号信息") {
                self.row("姓名", user.displayName ?? user.username ?? "—")
                self.row("用户名", user.username ?? "—")
                self.row("部门", (user.departmentName?.isEmpty ?? true) ? "—" : user.departmentName!)
                self.row("职位", user.position ?? "—")
                self.row("邮箱", user.email ?? "—", showsDivider: false)
            }
            Button(role: .destructive) {
                Task {
                    self.isLoggingOut = true
                    await OAAuthCoordinator.shared.logout()
                    self.isLoggingOut = false
                }
            } label: {
                Label("登出", systemImage: "rectangle.portrait.and.arrow.right")
            }
            .buttonStyle(.bordered)
            .disabled(self.isLoggingOut)
        }
    }

    private func row(_ title: String, _ value: String, showsDivider: Bool = true) -> some View {
        SettingsCardRow(title: title, showsDivider: showsDivider) {
            Text(value).font(.callout).foregroundStyle(.secondary)
        }
    }
}
