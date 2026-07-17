import AppKit
import OpenClawChatUI
import SwiftUI

/// Conversation rail for the primary chat window.
/// Gateway sessions + 天音 surface; new / search / rename / delete.
struct ChatSessionSidebar: View {
    @Bindable var viewModel: OpenClawChatViewModel
    @Binding var collapsed: Bool
    @Binding var surface: MainChatSurface
    var onNewTianyin: () -> Void = {}

    @State private var searchText = ""
    @State private var renamingKey: String?
    @State private var renameDraft = ""
    @State private var pendingDelete: OpenClawChatSessionEntry?
    @State private var hoverKey: String?

    private let railWidth: CGFloat = 228

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            self.header
            Divider()
            self.searchField
            Divider()
            self.sessionList
        }
        .frame(width: self.railWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        .alert(
            "Delete conversation?",
            isPresented: Binding(
                get: { self.pendingDelete != nil },
                set: { if !$0 { self.pendingDelete = nil } }))
        {
            Button("Cancel", role: .cancel) { self.pendingDelete = nil }
            Button("Delete", role: .destructive) {
                if let target = self.pendingDelete {
                    self.viewModel.deleteSession(target.key)
                }
                self.pendingDelete = nil
            }
        } message: {
            Text("This permanently removes the conversation and its transcript. This cannot be undone.")
        }
        .onAppear {
            self.viewModel.refreshSessions(limit: 200)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Text("Conversations")
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 0)
            Button {
                self.surface = .gateway
                self.viewModel.startNewSession(label: "New Chat")
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .help("New conversation (⌘N)")
            .keyboardShortcut("n", modifiers: .command)
            .accessibilityLabel("New conversation")

            Button {
                self.onNewTianyin()
            } label: {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .help("New 天音 conversation (⌘⇧N)")
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .accessibilityLabel("New 天音 conversation")

            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    self.collapsed = true
                }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .help("Hide conversation list")
            .accessibilityLabel("Hide conversation list")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.caption)
            TextField("Search", text: self.$searchText)
                .textFieldStyle(.plain)
                .font(.callout)
            if !self.searchText.isEmpty {
                Button {
                    self.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    // MARK: - List

    private var sessionList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                if self.showTianyinInList {
                    self.tianyinRow
                    if !self.filteredSessions.isEmpty {
                        Text("OpenClaw")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.top, 10)
                            .padding(.bottom, 2)
                    }
                }

                if self.filteredSessions.isEmpty, !self.showTianyinInList {
                    Text(self.searchText.isEmpty ? "No conversations yet." : "No matches.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(self.filteredSessions) { session in
                        self.row(for: session)
                    }
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 6)
        }
        .frame(maxHeight: .infinity)
    }

    private var showTianyinInList: Bool {
        let query = self.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty { return true }
        return "天音".localizedCaseInsensitiveContains(query)
            || "tianyin".localizedCaseInsensitiveContains(query)
            || "dify".localizedCaseInsensitiveContains(query)
    }

    private var tianyinRow: some View {
        let isActive = self.surface == .tianyin
        return Button {
            self.surface = .tianyin
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(isActive ? Color.accentColor : .secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("天音助手")
                            .font(.callout.weight(isActive ? .semibold : .regular))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text("知识库")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.purple.opacity(0.14), in: Capsule())
                            .foregroundStyle(.purple)
                    }
                    Text("与天音知识库对话")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isActive ? Color.accentColor.opacity(0.14) : Color.clear))
        .contextMenu {
            Button("新建天音对话") { self.onNewTianyin() }
        }
    }

    private var filteredSessions: [OpenClawChatSessionEntry] {
        let all = self.viewModel.sidebarSessions
        let query = self.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return all }
        return all.filter { session in
            self.title(for: session).localizedCaseInsensitiveContains(query)
                || session.key.localizedCaseInsensitiveContains(query)
        }
    }

    @ViewBuilder
    private func row(for session: OpenClawChatSessionEntry) -> some View {
        let isActive = self.viewModel.sessionKey == session.key
            || self.viewModel.isMainSessionKey(session.key)
            && self.viewModel.isMainSessionKey(self.viewModel.sessionKey)
        let isMain = self.viewModel.isMainSessionKey(session.key)
        let isHovering = self.hoverKey == session.key
        let isRenaming = self.renamingKey == session.key

        VStack(alignment: .leading, spacing: 4) {
            if isRenaming {
                HStack(spacing: 4) {
                    TextField("Name", text: self.$renameDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(.callout)
                        .onSubmit { self.commitRename(session) }
                    Button("Save") { self.commitRename(session) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    Button("Cancel") {
                        self.renamingKey = nil
                        self.renameDraft = ""
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(6)
            } else {
                Button {
                    self.surface = .gateway
                    self.viewModel.switchSession(to: session.key)
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(self.title(for: session))
                                    .font(.callout.weight(isActive && self.surface == .gateway ? .semibold : .regular))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                if isMain {
                                    Text("Main")
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            Text(self.subtitle(for: session))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        if isHovering || isActive {
                            self.rowMenu(for: session, isMain: isMain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isActive && self.surface == .gateway
                            ? Color.accentColor.opacity(0.14)
                            : (isHovering ? Color.primary.opacity(0.05) : Color.clear)))
                .onHover { hovering in
                    self.hoverKey = hovering ? session.key : (self.hoverKey == session.key ? nil : self.hoverKey)
                }
                .contextMenu {
                    Button("Rename…") { self.beginRename(session) }
                    if !isMain {
                        Button("Delete…", role: .destructive) {
                            self.pendingDelete = session
                        }
                    }
                    Divider()
                    Button("Copy session key") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(session.key, forType: .string)
                    }
                }
            }
        }
    }

    private func rowMenu(for session: OpenClawChatSessionEntry, isMain: Bool) -> some View {
        Menu {
            Button("Rename…") { self.beginRename(session) }
            if !isMain {
                Button("Delete…", role: .destructive) {
                    self.pendingDelete = session
                }
            }
            Divider()
            Button("Copy session key") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(session.key, forType: .string)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: - Helpers

    private func title(for session: OpenClawChatSessionEntry) -> String {
        if self.viewModel.isMainSessionKey(session.key) {
            let name = session.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return name.isEmpty ? "Main conversation" : name
        }
        let name = session.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !name.isEmpty { return name }
        // Fall back to a readable short key tail.
        if let tail = session.key.split(separator: ":").last, !tail.isEmpty {
            let s = String(tail)
            if s.hasPrefix("webchat-"), s.count > 16 {
                return "Chat " + s.suffix(8)
            }
            return s
        }
        return session.key
    }

    private func subtitle(for session: OpenClawChatSessionEntry) -> String {
        if let updatedAt = session.updatedAt, updatedAt > 0 {
            let date = Date(timeIntervalSince1970: updatedAt / 1000)
            return Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
        }
        return session.key
    }

    private func beginRename(_ session: OpenClawChatSessionEntry) {
        self.renamingKey = session.key
        self.renameDraft = self.title(for: session)
    }

    private func commitRename(_ session: OpenClawChatSessionEntry) {
        let draft = self.renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        self.renamingKey = nil
        self.renameDraft = ""
        guard !draft.isEmpty else { return }
        self.viewModel.renameSession(session.key, label: draft)
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
}
