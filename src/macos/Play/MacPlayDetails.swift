// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI
import AppKit

/// Lightweight, restorable data for a separate, resizable screenshot window.
struct MacPlayGallery: Codable, Hashable {
    let title: String
    let urls: [String]
    let selected: Int
}

struct MacPlayDetails<Controls: View, Compatibility: View>: View {
    let app: PlayAPI.PlayApp
    @ViewBuilder var controls: () -> Controls
    @ViewBuilder var compatibility: () -> Compatibility
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if let feature = app.feature, let url = PlayImages.sized(feature, height: 600) {
                AsyncImage(url: url) { image in image.resizable().scaledToFit() }
                    placeholder: { Color.clear }.frame(maxHeight: 230).clipShape(RoundedRectangle(cornerRadius: 14))
            }
            HStack(alignment: .top, spacing: 16) {
                PlayIcon(url: app.iconURL, size: 80)
                VStack(alignment: .leading, spacing: 6) {
                    Text(app.title).font(.title.bold()).textSelection(.enabled)
                    Text(app.developer).foregroundStyle(.secondary)
                    if !app.award.isEmpty { Label(app.award, systemImage: "seal.fill").font(.caption) }
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), alignment: .leading)], alignment: .leading, spacing: 14) {
                if app.rating > 0 { stat("Rating", String(format: "%.1f ★", app.rating)) }
                if !app.reviews.isEmpty { stat("Reviews", app.reviews) }
                if !app.installs.isEmpty { stat("Downloads", app.installs) }
                if !app.contentRating.isEmpty { stat("Rated for", app.contentRating) }
                if app.sizeBytes > 0 { stat("Size", ByteCountFormatter.string(fromByteCount: app.sizeBytes, countStyle: .file)) }
            }
            controls()
            media
            if !app.highlights.isEmpty {
                GroupBox("Highlights") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(app.highlights.enumerated()), id: \.offset) { _, line in Label(line, systemImage: "sparkles") }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                Text(LocalizedStringKey(app.isGame ? "About this game" : "About this app")).font(.title2.bold())
                if !app.tagline.isEmpty { Text(app.tagline).font(.headline) }
                MacPlayText(html: app.summary, lines: 8)
                if !app.tags.isEmpty {
                    ScrollView(.horizontal) { HStack { ForEach(app.tags, id: \.self) { Text($0).padding(8).background(.quaternary, in: Capsule()) } } }
                }
            }
            if !app.whatsNew.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack { Text("What's new").font(.title2.bold()); Spacer(); Text(app.updated).foregroundStyle(.secondary) }
                    MacPlayText(html: app.whatsNew, lines: 5)
                }
            }
            compatibility()
            GroupBox("Information") {
                VStack(alignment: .leading, spacing: 12) {
                    info("Developer", app.developer)
                    info("Updated", app.updated)
                    info("Released", app.released)
                    info("Version", app.versionString.isEmpty ? String(app.versionCode) : app.versionString)
                    info("Ads", app.ads)
                    info("In-app purchases", app.purchases)
                    info("Package", app.id)
                    link("Website", app.website)
                    link("Privacy policy", app.privacy)
                    if !app.email.isEmpty, let url = URL(string: "mailto:" + app.email) { Link("Email", destination: url) }
                    link("View on Google Play", "https://play.google.com/store/apps/details?id=" + app.id)
                }.padding(10)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
    }
    private func stat(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(value).font(.headline); Text(title).font(.caption).foregroundStyle(.secondary) }
    }
    @ViewBuilder private func info(_ title: LocalizedStringKey, _ value: String) -> some View {
        if !value.isEmpty { LabeledContent(title) { Text(value).textSelection(.enabled).multilineTextAlignment(.trailing) } }
    }
    @ViewBuilder private func link(_ title: LocalizedStringKey, _ value: String) -> some View {
        if let url = PlayImages.webURL(value) { Link(title, destination: url) }
    }
    @ViewBuilder private var media: some View {
        if !app.screenshotURLs.isEmpty || app.trailer != nil {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    if let trailer = app.trailer, let url = PlayImages.webURL(trailer.url) {
                        Link(destination: url) {
                            VStack {
                                ZStack {
                                    AsyncImage(url: trailer.thumbnail.flatMap(PlayImages.webURL)) { image in image.resizable().scaledToFit() }
                                        placeholder: { Color.secondary.opacity(0.12) }
                                    Image(systemName: "play.circle.fill").font(.system(size: 46))
                                }.frame(width: 320, height: 180)
                                Text("Watch trailer")
                            }
                        }
                    }
                    ForEach(app.screenshotURLs.indices, id: \.self) { i in
                        let ratio = i < app.screenshotRatios.count ? app.screenshotRatios[i] : 0
                        Button {
                            openWindow(id: "play-screenshots", value: MacPlayGallery(title: app.title, urls: app.screenshotURLs, selected: i))
                        } label: {
                            AsyncImage(url: PlayImages.sized(app.screenshotURLs[i], height: 500)) { image in image.resizable().scaledToFit() }
                                placeholder: { Image(systemName: "photo").foregroundStyle(.secondary) }
                                .frame(width: 220 * (ratio > 0 && ratio.isFinite ? min(4, max(0.2, ratio)) : 0.6), height: 220)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(.plain).accessibilityLabel("Screenshot \(i + 1)")
                    }
                }
            }
        }
    }
}

private struct MacPlayText: View {
    let html: String
    let lines: Int
    @State private var expanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(PlayText.attributed(html)).lineLimit(expanded ? nil : lines)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            if PlayText.plain(html).count > lines * 20 || PlayText.plain(html).split(separator: "\n").count >= lines {
                Button(LocalizedStringKey(expanded ? "Show less" : "Show more")) { expanded.toggle() }.buttonStyle(.link)
            }
        }
    }
}

struct MacPlayGalleryView: View {
    let gallery: MacPlayGallery
    @State private var index: Int
    @State private var zoom: CGFloat = 1
    init(gallery: MacPlayGallery) {
        self.gallery = gallery
        _index = State(initialValue: max(0, min(gallery.selected, gallery.urls.count - 1)))
    }
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button { if index > 0 { index -= 1 } } label: { Label("Previous", systemImage: "chevron.left") }
                    .keyboardShortcut(.leftArrow, modifiers: []).disabled(index <= 0)
                Text("\(gallery.urls.isEmpty ? 0 : index + 1) / \(gallery.urls.count)").monospacedDigit()
                Button { if index + 1 < gallery.urls.count { index += 1 } } label: { Label("Next", systemImage: "chevron.right") }
                    .keyboardShortcut(.rightArrow, modifiers: []).disabled(index + 1 >= gallery.urls.count)
                Spacer()
                Button { zoom = max(1, zoom - 0.5) } label: { Label("Zoom out", systemImage: "minus.magnifyingglass") }.disabled(zoom <= 1)
                Button { zoom = min(4, zoom + 0.5) } label: { Label("Zoom in", systemImage: "plus.magnifyingglass") }.disabled(zoom >= 4)
                Button("Full Screen") { NSApp.keyWindow?.toggleFullScreen(nil) }
            }
            GeometryReader { bounds in
                ScrollView([.horizontal, .vertical]) {
                    if gallery.urls.indices.contains(index) {
                        AsyncImage(url: PlayImages.sized(gallery.urls[index], height: 1600)) { phase in
                            if let image = phase.image { image.resizable().scaledToFit() }
                            else if phase.error != nil { ContentUnavailableView("Image unavailable", systemImage: "photo") }
                            else { ProgressView() }
                        }.frame(width: bounds.size.width * zoom, height: bounds.size.height * zoom)
                    } else { ContentUnavailableView("No screenshots", systemImage: "photo") }
                }
            }
        }.padding(16).frame(minWidth: 650, minHeight: 460).navigationTitle(gallery.title)
            .onChange(of: index) { _, _ in zoom = 1 }
    }
}

struct PlayIcon: View {
    let url: String?
    let size: CGFloat
    var body: some View {
        AsyncImage(url: url.flatMap(PlayImages.webURL)) { image in image.resizable().scaledToFit() }
            placeholder: { Image(systemName: "app.fill").resizable().scaledToFit().foregroundStyle(.secondary).padding(8) }
            .frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.2))
    }
}
