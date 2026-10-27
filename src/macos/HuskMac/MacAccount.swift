// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import SharedLibrary

@MainActor enum MacAccountLibrary {
    static func rows(_ games: [LibraryGame], seconds: ((String) -> Double)? = nil) -> [[String: Any]] {
        let iso = ISO8601DateFormatter()
        return games.prefix(2000).compactMap { game in
            guard let package = game.packageName, !package.isEmpty else { return nil }
            // Match the shared launcher classification for translated applications.
            let isGame = game.engine != "Flutter" && game.webKind == nil
            return ["package": package, "name": String(game.title.prefix(80)), "platform": "android",
                    "type": isGame ? "game" : "app", "playtimeSeconds": (seconds?(game.id) ?? Playtime.seconds(game.id)).rounded(),
                    "lastPlayed": game.lastPlayed.map { iso.string(from: $0) } ?? NSNull()]
        }
    }
}

struct MacAccountView: View {
    @ObservedObject private var account = Account.shared
    @State private var registering = false
    @State private var username = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var message: String?
    @State private var working = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 16) {
                    AccountAvatar(size: 72)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(account.user?.displayName ?? String(localized: "Husk Account")).font(.largeTitle.bold())
                        if let user = account.user { Text("@\(user.username)").foregroundStyle(.secondary) }
                        else { Text("Your profile, library and playtime.").foregroundStyle(.secondary) }
                    }
                }
                if let user = account.user, account.signedIn {
                    HStack(spacing: 28) {
                        LabeledContent("Games", value: String(user.stats.games))
                        LabeledContent("Apps", value: String(user.stats.apps))
                        LabeledContent("Playtime", value: Playtime.text(user.stats.playtimeSeconds))
                    }
                    GroupBox("Profile") {
                        VStack(alignment: .leading, spacing: 12) {
                            TextField("Display name", text: $displayName)
                            HStack {
                                Button("Save name") { perform { try await account.update(displayName: displayName) } }
                                    .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                Button("Choose avatar…") { chooseAvatar() }
                                Button("Remove avatar") { perform { try await account.update(avatarPNG: .some(nil)) } }
                            }
                        }.padding(8)
                    }
                    HStack {
                        Button("Sync library") { perform { await account.syncLibrary(); message = account.error } }
                        Button("Refresh profile") { perform { await account.refresh(); message = account.error } }
                        Spacer()
                        Button("Sign out") { perform { await account.signOut() } }
                    }
                    Text("Signing in syncs application names, package IDs, playtime and recent activity to your Husk profile. Game saves stay on this Mac.")
                        .font(.caption).foregroundStyle(.secondary)
                    if !user.recent.isEmpty {
                        Text("Recently played").font(.title2.bold())
                        ForEach(user.recent) { item in
                            HStack { Text(item.name); Spacer(); Text(Playtime.text(item.playtimeSeconds)).foregroundStyle(.secondary) }
                        }
                    }
                    if !user.achievements.isEmpty {
                        Text("Achievements").font(.title2.bold())
                        ForEach(user.achievements) { item in
                            Label { VStack(alignment: .leading) { Text(item.title).bold(); Text(item.detail).font(.caption).foregroundStyle(.secondary) } }
                            icon: { Image(systemName: item.unlocked ? "checkmark.seal.fill" : "lock") }
                        }
                    }
                } else {
                    Picker("Account", selection: $registering) { Text("Sign in").tag(false); Text("Create account").tag(true) }.pickerStyle(.segmented)
                    TextField("Username", text: $username).textContentType(.username)
                    SecureField("Password", text: $password).textContentType(registering ? .newPassword : .password)
                    if registering { TextField("Display name", text: $displayName) }
                    Text("Signing in syncs application names, package IDs, playtime and recent activity to your Husk profile. Game saves stay on this Mac.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button(LocalizedStringKey(registering ? "Create account" : "Sign in")) {
                        perform {
                            if registering { try await account.signUp(username: username, password: password, displayName: displayName) }
                            else { try await account.signIn(username: username, password: password) }
                            password = ""; displayName = account.user?.displayName ?? ""; message = account.error
                        }
                    }.buttonStyle(.borderedProminent).disabled(username.isEmpty || password.isEmpty || (registering && displayName.isEmpty))
                }
                if working || account.busy { ProgressView() }
                if let message { Text(message).foregroundStyle(.red).textSelection(.enabled) }
            }.textFieldStyle(.roundedBorder).disabled(working || account.busy).padding(30).frame(maxWidth: 760)
        }
        .onAppear { displayName = account.user?.displayName ?? "" }
    }
    private func perform(_ operation: @escaping () async throws -> Void) {
        working = true; message = nil
        Task { defer { working = false }; do { try await operation() } catch { message = error.localizedDescription } }
    }
    private func chooseAvatar() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url),
              let png = Account.avatarPNG(image) else { return }
        perform { try await account.update(avatarPNG: .some(png)) }
    }
}
