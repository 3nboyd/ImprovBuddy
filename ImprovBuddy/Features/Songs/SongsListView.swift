import Foundation
import PDFKit
import QuickLook
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UIKit

enum SongSortMode: String, CaseIterable, Identifiable {
    case recent
    case title
    case tempo

    var id: String { rawValue }

    var label: String {
        switch self {
        case .recent: "Recent"
        case .title: "Title"
        case .tempo: "Tempo"
        }
    }
}

struct SongLibraryFilterState: Equatable {
    var selectedTags: Set<String> = []
    var searchText = ""
    var sortMode: SongSortMode = .recent
    var showUntagged = false

    var hasActiveFilters: Bool {
        !selectedTags.isEmpty || showUntagged || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    mutating func clear() {
        selectedTags.removeAll()
        showUntagged = false
        searchText = ""
    }
}

struct SongTagCatalog: Equatable {
    var allTags: [String]
    var recentTags: [String]

    static func build(from songs: [Song], recentTags: [String]) -> SongTagCatalog {
        let all = songs
            .flatMap(\.tags)
            .map(Song.normalizedTag)
            .filter { !$0.isEmpty }

        let knownDefaults = Song.defaultTagSuggestions.map(Song.normalizedTag)
        let dynamicTags = Array(Set(all)).sorted()
        let allSorted = knownDefaults + dynamicTags.filter { !knownDefaults.contains($0) }
        let filteredRecent = recentTags
            .map(Song.normalizedTag)
            .filter { allSorted.contains($0) }

        return SongTagCatalog(
            allTags: allSorted,
            recentTags: Array(NSOrderedSet(array: filteredRecent).compactMap { $0 as? String })
        )
    }
}

@MainActor
final class SongTagRecentsStore: ObservableObject {
    @Published private(set) var recentTags: [String]
    private let defaults: UserDefaults
    private let key = "songs.tagRecents.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.recentTags = defaults.stringArray(forKey: key) ?? []
    }

    func markUsed(tag: String) {
        let normalized = Song.normalizedTag(tag)
        guard !normalized.isEmpty else { return }
        recentTags.removeAll { $0 == normalized }
        recentTags.insert(normalized, at: 0)
        if recentTags.count > 16 {
            recentTags.removeLast(recentTags.count - 16)
        }
        defaults.set(recentTags, forKey: key)
    }
}

enum PDFMetadataSource: String, Codable {
    case documentAttributes
    case firstPageHeuristic
    case fileNameFallback
}

struct PDFSongMetadata: Equatable {
    var title: String
    var author: String?
    var confidence: Double
    var source: PDFMetadataSource
}

enum PDFSongMetadataExtractor {
    static func extract(from url: URL) -> PDFSongMetadata {
        guard let document = PDFDocument(url: url) else {
            return PDFSongMetadata(
                title: fallbackTitle(from: url),
                author: nil,
                confidence: 0.35,
                source: .fileNameFallback
            )
        }

        let attributes = document.documentAttributes ?? [:]
        let attributeTitle = sanitize(attributes[PDFDocumentAttribute.titleAttribute] as? String)
        let attributeAuthor = sanitize(attributes[PDFDocumentAttribute.authorAttribute] as? String)
        if let attributeTitle, !attributeTitle.isEmpty {
            return PDFSongMetadata(
                title: attributeTitle,
                author: attributeAuthor,
                confidence: 0.95,
                source: .documentAttributes
            )
        }

        let firstPageText = sanitize(document.page(at: 0)?.string)
        return extract(
            documentMetadataTitle: attributeTitle,
            documentMetadataAuthor: attributeAuthor,
            firstPageText: firstPageText,
            fileName: url.deletingPathExtension().lastPathComponent
        )
    }

    static func extract(
        documentMetadataTitle: String?,
        documentMetadataAuthor: String?,
        firstPageText: String?,
        fileName: String
    ) -> PDFSongMetadata {
        if let title = sanitize(documentMetadataTitle), !title.isEmpty {
            return PDFSongMetadata(
                title: title,
                author: sanitize(documentMetadataAuthor),
                confidence: 0.95,
                source: .documentAttributes
            )
        }

        if let text = sanitize(firstPageText), !text.isEmpty {
            let lines = text
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            let titleCandidate = lines.first(where: isLikelyTitle)
            let authorCandidate = lines.first(where: isLikelyAuthor)
            if let titleCandidate {
                return PDFSongMetadata(
                    title: titleCandidate,
                    author: authorCandidate.flatMap(cleanAuthorLine),
                    confidence: 0.72,
                    source: .firstPageHeuristic
                )
            }
        }

        return PDFSongMetadata(
            title: fallbackTitle(fromRawName: fileName),
            author: nil,
            confidence: 0.35,
            source: .fileNameFallback
        )
    }

    private static func isLikelyTitle(_ line: String) -> Bool {
        if line.count < 2 || line.count > 90 { return false }
        if line.lowercased().hasPrefix("page ") { return false }
        if line.range(of: "copyright", options: .caseInsensitive) != nil { return false }
        if line.contains("@") || line.contains("http") { return false }
        let digitCount = line.filter(\.isNumber).count
        return digitCount <= 3
    }

    private static func isLikelyAuthor(_ line: String) -> Bool {
        let lowered = line.lowercased()
        return lowered.hasPrefix("by ") || lowered.contains("composer")
    }

    private static func cleanAuthorLine(_ line: String) -> String {
        let lowered = line.lowercased()
        if lowered.hasPrefix("by ") {
            return String(line.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return line.replacingOccurrences(of: "Composer:", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func fallbackTitle(from url: URL) -> String {
        fallbackTitle(fromRawName: url.deletingPathExtension().lastPathComponent)
    }

    private static func fallbackTitle(fromRawName rawName: String) -> String {
        rawName
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sanitize(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}

enum SongMediaStorage {
    static let folderName = "SongMedia"

    static var allowedImportTypes: [UTType] {
        [.pdf, .image]
    }

    static func copyAttachments(from urls: [URL]) throws -> [SongAttachment] {
        guard !urls.isEmpty else { return [] }
        let destinationFolder = try mediaFolderURL()

        var attachments: [SongAttachment] = []
        attachments.reserveCapacity(urls.count)

        for source in urls {
            guard let kind = attachmentKind(for: source) else { continue }
            let fileName = source.lastPathComponent.replacingOccurrences(of: "/", with: "-")
            let destination = destinationFolder.appendingPathComponent("\(UUID().uuidString)-\(fileName)")

            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)

            attachments.append(
                SongAttachment(
                    kind: kind,
                    path: destination.absoluteString,
                    originalFileName: source.lastPathComponent
                )
            )
        }

        return attachments
    }

    static func titleFallback(from attachment: SongAttachment?) -> String {
        guard let attachment else { return "Untitled Song" }
        let rawName = (attachment.originalFileName as NSString).deletingPathExtension
        let cleaned = rawName
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Untitled Song" : cleaned
    }

    private static func mediaFolderURL() throws -> URL {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        let folder = documents.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func attachmentKind(for source: URL) -> SongAttachmentKind? {
        let ext = source.pathExtension.lowercased()
        if ext == "pdf" {
            return .pdf
        }
        if let type = UTType(filenameExtension: ext), type.conforms(to: .image) {
            return .image
        }
        return nil
    }
}

struct SongQuickTagPopup: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let song: Song
    let allTags: [String]
    var onTagUsed: (String) -> Void = { _ in }

    @State private var newTag = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack {
                    TextField("Add tag", text: $newTag)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        addTag()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(Song.normalizedTag(newTag).isEmpty)
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(allTags, id: \.self) { tag in
                            Button {
                                toggle(tag: tag)
                            } label: {
                                HStack {
                                    Text(tag)
                                    Spacer()
                                    Image(systemName: song.hasTag(tag) ? "checkmark.circle.fill" : "circle")
                                }
                                .font(.body.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding()
            .navigationTitle("Quick Tags")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Label("Back", systemImage: "chevron.backward")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 10)
                .background(.ultraThinMaterial)
                .overlay(alignment: .top) {
                    Divider().opacity(0.2)
                }
            }
        }
    }

    private func addTag() {
        let normalized = Song.normalizedTag(newTag)
        guard !normalized.isEmpty else { return }
        song.addTag(normalized)
        song.touch()
        try? modelContext.save()
        onTagUsed(normalized)
        newTag = ""
    }

    private func toggle(tag: String) {
        if song.hasTag(tag) {
            song.removeTag(tag)
        } else {
            song.addTag(tag)
            onTagUsed(tag)
        }
        song.touch()
        try? modelContext.save()
    }
}

struct SongTagManagerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let songs: [Song]
    var onTagUsed: (String) -> Void = { _ in }

    @State private var renameDrafts: [String: String] = [:]

    private var allTags: [String] {
        let knownDefaults = Song.defaultTagSuggestions.map(Song.normalizedTag)
        let dynamicTags = Array(Set(songs.flatMap(\.tags).map(Song.normalizedTag))).sorted()
        return knownDefaults + dynamicTags.filter { !knownDefaults.contains($0) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if allTags.isEmpty {
                    ContentUnavailableView("No tags yet", systemImage: "tag")
                } else {
                    List {
                        ForEach(allTags, id: \.self) { tag in
                            HStack(spacing: 8) {
                                TextField(tag, text: Binding(
                                    get: { renameDrafts[tag] ?? tag },
                                    set: { renameDrafts[tag] = $0 }
                                ))
                                .textFieldStyle(.roundedBorder)

                                Button("Rename") {
                                    renameTag(from: tag, to: renameDrafts[tag] ?? tag)
                                }
                                .buttonStyle(.bordered)

                                Button(role: .destructive) {
                                    deleteTag(tag)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .padding()
            .navigationTitle("Manage Tags")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Label("Back", systemImage: "chevron.backward")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 10)
                .background(.ultraThinMaterial)
                .overlay(alignment: .top) {
                    Divider().opacity(0.2)
                }
            }
        }
    }

    private func renameTag(from oldTag: String, to rawNewTag: String) {
        let newTag = Song.normalizedTag(rawNewTag)
        guard !oldTag.isEmpty else { return }
        for song in songs where song.hasTag(oldTag) {
            song.renameTag(from: oldTag, to: newTag)
            song.touch()
        }
        try? modelContext.save()
        if !newTag.isEmpty {
            onTagUsed(newTag)
        }
    }

    private func deleteTag(_ tag: String) {
        for song in songs where song.hasTag(tag) {
            song.removeTag(tag)
            song.touch()
        }
        try? modelContext.save()
    }
}

struct SongsWorkspaceView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appEnvironment: AppEnvironment
    @Query(sort: \Song.updatedAt, order: .reverse) private var songs: [Song]

    @StateObject private var recentTagsStore = SongTagRecentsStore()

    @State private var filter = SongLibraryFilterState()
    @State private var showingCreateSheet = false
    @State private var editingSong: Song?
    @State private var quickTagSong: Song?
    @State private var showingTagManager = false
    @State private var detailRoute: SongDetailRoute?
    @State private var showingMediaImport = false
    @State private var importMessage = ""

    private var tagCatalog: SongTagCatalog {
        SongTagCatalog.build(from: songs, recentTags: recentTagsStore.recentTags)
    }

    private var availableTags: [String] {
        let merged = tagCatalog.recentTags + tagCatalog.allTags
        return Array(NSOrderedSet(array: merged).compactMap { $0 as? String })
    }

    private var filteredSongs: [Song] {
        let query = filter.searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let base = songs.filter { song in
            let matchesSearch: Bool = {
                guard !query.isEmpty else { return true }
                let values = [song.title, song.composer ?? ""] + song.tags
                return values.joined(separator: " ").lowercased().contains(query)
            }()

            let tagSet = Set(song.tags)
            let matchesTag = filter.selectedTags.isEmpty ? true : !filter.selectedTags.isDisjoint(with: tagSet)
            let matchesUntagged = filter.showUntagged && song.tags.isEmpty
            let matchesFolder = matchesTag || matchesUntagged

            return matchesSearch && matchesFolder
        }

        switch filter.sortMode {
        case .recent:
            return base.sorted { $0.updatedAt > $1.updatedAt }
        case .title:
            return base.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .tempo:
            return base.sorted { $0.defaultTempoBPM < $1.defaultTempoBPM }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                topBar
                tagRail
                songsList
            }
            .navigationTitle("Songs")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingCreateSheet) {
                SongEditorView(song: nil)
            }
            .sheet(item: $editingSong) { song in
                SongEditorView(song: song)
            }
            .sheet(item: $quickTagSong) { song in
                SongQuickTagPopup(song: song, allTags: availableTags) { tag in
                    recentTagsStore.markUsed(tag: tag)
                }
            }
            .sheet(isPresented: $showingTagManager) {
                SongTagManagerSheet(songs: songs) { tag in
                    recentTagsStore.markUsed(tag: tag)
                }
            }
            .navigationDestination(item: $detailRoute) { route in
                SongDetailPagerView(
                    songs: filteredSongs,
                    initialSongID: route.initialSongID
                )
            }
            .fileImporter(
                isPresented: $showingMediaImport,
                allowedContentTypes: SongMediaStorage.allowedImportTypes,
                allowsMultipleSelection: true
            ) { result in
                importSongFromMedia(result)
            }
            .onAppear(perform: migrateLegacySongMediaIfNeeded)
        }
    }

    private var topBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search title, composer, tags", text: $filter.searchText)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                }
                .padding(.horizontal, 10)
                .frame(height: 38)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                Menu {
                    Picker("Sort", selection: $filter.sortMode) {
                        ForEach(SongSortMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .frame(width: 38, height: 38)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }

            HStack(spacing: 8) {
                Button {
                    showingCreateSheet = true
                } label: {
                    Label("New", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    showingMediaImport = true
                } label: {
                    Label("Import", systemImage: "doc.richtext")
                }
                .buttonStyle(.bordered)

                Button {
                    showingTagManager = true
                } label: {
                    Label("Tags", systemImage: "tag")
                }
                .buttonStyle(.bordered)

                Spacer()
            }

            if !importMessage.isEmpty {
                Text(importMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var tagRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                folderChip(
                    title: "All",
                    selected: filter.selectedTags.isEmpty && !filter.showUntagged
                ) {
                    filter.selectedTags.removeAll()
                    filter.showUntagged = false
                }

                folderChip(
                    title: "Untagged",
                    selected: filter.showUntagged
                ) {
                    filter.showUntagged.toggle()
                }

                ForEach(availableTags, id: \.self) { tag in
                    folderChip(
                        title: tag,
                        selected: filter.selectedTags.contains(tag)
                    ) {
                        if filter.selectedTags.contains(tag) {
                            filter.selectedTags.remove(tag)
                        } else {
                            filter.selectedTags.insert(tag)
                            recentTagsStore.markUsed(tag: tag)
                        }
                    }
                }

                if filter.hasActiveFilters {
                    Button("Clear") {
                        filter.clear()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(Color.black.opacity(0.2))
    }

    private var songsList: some View {
        List {
            if filteredSongs.isEmpty {
                ContentUnavailableView(
                    "No Songs Found",
                    systemImage: "music.note.list",
                    description: Text("Create a song or adjust your tag filters.")
                )
            } else {
                ForEach(filteredSongs) { song in
                    SongWorkspaceRow(song: song)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            detailRoute = SongDetailRoute(initialSongID: song.id)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                delete(song)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                quickTagSong = song
                            } label: {
                                Label("Tags", systemImage: "tag")
                            }
                            .tint(appEnvironment.accentColor)
                        }
                }
            }
        }
        .listStyle(.plain)
    }

    private func folderChip(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(selected ? appEnvironment.accentColor.opacity(0.3) : Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(selected ? appEnvironment.accentColor : Color.white.opacity(0.1), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func delete(_ song: Song) {
        modelContext.delete(song)
        try? modelContext.save()
    }

    private func importSongFromMedia(_ result: Result<[URL], Error>) {
        guard case let .success(urls) = result, !urls.isEmpty else { return }

        let securedURLs = urls.filter { $0.startAccessingSecurityScopedResource() }
        defer {
            for securedURL in securedURLs {
                securedURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let attachments = try SongMediaStorage.copyAttachments(from: urls)
            guard !attachments.isEmpty else {
                importMessage = "Import failed: No supported file types selected."
                return
            }

            let firstPDF = attachments.first(where: { $0.kind == .pdf })
            let metadata: PDFSongMetadata? = {
                guard
                    let firstPDF,
                    let pdfURL = firstPDF.resolvedURL
                else { return nil }
                return PDFSongMetadataExtractor.extract(from: pdfURL)
            }()

            let title = metadata?.title ?? SongMediaStorage.titleFallback(from: attachments.first)
            let newSong = Song(
                title: title,
                composer: metadata?.author,
                styleTags: [],
                defaultTempoBPM: 120,
                feel: .swing,
                timeSignatureTop: 4,
                timeSignatureBottom: 4,
                form: [],
                pdfReferencePath: firstPDF?.path,
                attachments: attachments
            )
            modelContext.insert(newSong)
            try? modelContext.save()

            importMessage = "Imported \(attachments.count) file\(attachments.count == 1 ? "" : "s") into \"\(title)\"."
            editingSong = newSong
        } catch {
            importMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    private func migrateLegacySongMediaIfNeeded() {
        var didMutate = false
        for song in songs {
            if song.migrateLegacyPDFReferenceIfNeeded() {
                song.touch()
                didMutate = true
            }
        }
        if didMutate {
            try? modelContext.save()
        }
    }
}

struct SongsListView: View {
    var body: some View {
        SongsWorkspaceView()
    }
}

private struct SongWorkspaceRow: View {
    let song: Song

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(song.title)
                    .font(.headline)
                Spacer()
                Text(song.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Text("\(Int(song.defaultTempoBPM)) BPM")
                Text(song.feel.displayName)
                Text("\(song.timeSignatureTop)/\(song.timeSignatureBottom)")
                if let composer = song.composer, !composer.isEmpty {
                    Text(composer)
                }
                if !song.mediaAttachments.isEmpty {
                    Text("\(song.mediaAttachments.count) file\(song.mediaAttachments.count == 1 ? "" : "s")")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if !song.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(song.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.09), in: Capsule())
                        }
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }
}

private struct SongDetailRoute: Identifiable, Hashable {
    let id = UUID()
    let initialSongID: UUID
}

private struct SongDetailPagerView: View {
    @Environment(\.dismiss) private var dismiss
    let songs: [Song]
    let initialSongID: UUID?

    @State private var selectedIndex = 0

    private var selectedSong: Song? {
        guard songs.indices.contains(selectedIndex) else { return nil }
        return songs[selectedIndex]
    }

    var body: some View {
        Group {
            if songs.isEmpty {
                ContentUnavailableView("No songs", systemImage: "music.note.list")
            } else {
                TabView(selection: $selectedIndex) {
                    ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                        SongDetailPage(song: song)
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                Button {
                    dismiss()
                } label: {
                    Label("Back", systemImage: "chevron.backward")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)

                Spacer()

                if let selectedSong {
                    VStack(spacing: 2) {
                        Text(selectedSong.title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            ForEach(Array(songs.indices), id: \.self) { index in
                                Circle()
                                    .fill(index == selectedIndex ? Color.white : Color.white.opacity(0.35))
                                    .frame(width: 6, height: 6)
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                }

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .padding(.bottom, 8)
            .background(.ultraThinMaterial)
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            if let initialSongID,
               let index = songs.firstIndex(where: { $0.id == initialSongID }) {
                selectedIndex = index
            } else {
                selectedIndex = 0
            }
        }
    }
}

private struct SongDetailPage: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let song: Song

    @State private var showingMediaAttachPicker = false
    @State private var mediaAttachMessage = ""
    @State private var previewIndex = 0
    @State private var twoPageMode = false
    @State private var readerRefreshToken = UUID()
    @State private var markupSession: SongMarkupSession?

    private var attachments: [SongAttachment] {
        song.mediaAttachments
    }

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    private func readerHeight(for containerHeight: CGFloat) -> CGFloat {
        if isRegularWidth {
            // Favor music-first reading on iPad/regular-width layouts.
            let target = containerHeight - 120
            return min(max(target, 620), containerHeight * 0.95)
        }

        let target = containerHeight * 0.74
        return min(max(target, 360), containerHeight * 0.86)
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        if let composer = song.composer, !composer.isEmpty {
                            Text(composer)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Text("\(Int(song.defaultTempoBPM)) BPM • \(song.feel.displayName) • \(song.timeSignatureTop)/\(song.timeSignatureBottom)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if !song.tags.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(song.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.white.opacity(0.08), in: Capsule())
                            }
                        }
                    }

                    if attachments.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("No sheet music attached yet.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                            Button {
                                showingMediaAttachPicker = true
                            } label: {
                                Label("Attach Sheet Music", systemImage: "paperclip")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)

                            if !mediaAttachMessage.isEmpty {
                                Text(mediaAttachMessage)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.top, 8)
                    } else {
                        SongAttachmentReaderPanel(
                            attachments: attachments,
                            pageIndex: $previewIndex,
                            twoPageMode: $twoPageMode,
                            refreshToken: readerRefreshToken
                        ) { selectedPageIndex in
                            markupSession = SongMarkupSession(initialIndex: selectedPageIndex)
                        }
                        .frame(height: readerHeight(for: proxy.size.height))
                        .padding(.horizontal, -16)
                        .frame(maxWidth: .infinity)

                        HStack {
                            Button("Add Files") {
                                showingMediaAttachPicker = true
                            }
                            .buttonStyle(.borderedProminent)
                            Spacer()
                        }

                        attachmentList

                        if !mediaAttachMessage.isEmpty {
                            Text(mediaAttachMessage)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .fileImporter(
            isPresented: $showingMediaAttachPicker,
            allowedContentTypes: SongMediaStorage.allowedImportTypes,
            allowsMultipleSelection: true
        ) { result in
            attachMedia(result)
        }
        .sheet(item: $markupSession) { session in
            SongMarkupEditorSheet(
                attachments: attachments,
                initialIndex: session.initialIndex
            ) {
                readerRefreshToken = UUID()
            }
        }
        .onAppear {
            if song.migrateLegacyPDFReferenceIfNeeded() {
                song.touch()
                try? modelContext.save()
            }
            if attachments.indices.contains(previewIndex) == false {
                previewIndex = max(0, attachments.count - 1)
            }
            if attachments.count < 2 {
                twoPageMode = false
            }
        }
    }

    private var attachmentList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(attachments.enumerated()), id: \.element.id) { index, attachment in
                HStack(spacing: 10) {
                    Image(systemName: attachment.kind == .pdf ? "doc.richtext" : "photo")
                        .foregroundStyle(.secondary)
                    Text(attachment.originalFileName)
                        .font(.subheadline)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        removeAttachment(id: attachment.id)
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    previewIndex = index
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private func attachMedia(_ result: Result<[URL], Error>) {
        guard case let .success(urls) = result, !urls.isEmpty else { return }

        let securedURLs = urls.filter { $0.startAccessingSecurityScopedResource() }
        defer {
            for securedURL in securedURLs {
                securedURL.stopAccessingSecurityScopedResource()
            }
        }

        let previousCount = attachments.count
        do {
            let imported = try SongMediaStorage.copyAttachments(from: urls)
            guard !imported.isEmpty else {
                mediaAttachMessage = "No supported files selected."
                return
            }

            song.addAttachments(imported)
            if song.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if
                    let firstPDF = imported.first(where: { $0.kind == .pdf }),
                    let pdfURL = firstPDF.resolvedURL
                {
                    let metadata = PDFSongMetadataExtractor.extract(from: pdfURL)
                    song.title = metadata.title
                    if song.composer?.isEmpty ?? true {
                        song.composer = metadata.author
                    }
                } else {
                    song.title = SongMediaStorage.titleFallback(from: imported.first)
                }
            }

            song.touch()
            try? modelContext.save()
            previewIndex = min(max(0, previousCount), max(0, song.mediaAttachments.count - 1))
            if song.mediaAttachments.count < 2 {
                twoPageMode = false
            }
            mediaAttachMessage = "Added \(imported.count) file\(imported.count == 1 ? "" : "s")."
        } catch {
            mediaAttachMessage = "Attach failed: \(error.localizedDescription)"
        }
    }

    private func removeAttachment(id: UUID) {
        song.removeAttachment(id: id)
        song.touch()
        try? modelContext.save()
        previewIndex = min(previewIndex, max(0, attachments.count - 1))
        if attachments.count < 2 {
            twoPageMode = false
        }
    }
}

private struct SongAttachmentReaderPanel: View {
    let attachments: [SongAttachment]
    @Binding var pageIndex: Int
    @Binding var twoPageMode: Bool
    let refreshToken: UUID
    var onMarkup: (Int) -> Void

    private var clampedPageIndex: Int {
        min(max(0, pageIndex), max(0, attachments.count - 1))
    }

    private var rightPageIndex: Int? {
        guard twoPageMode else { return nil }
        let candidate = clampedPageIndex + 1
        return attachments.indices.contains(candidate) ? candidate : nil
    }

    private var pageLabel: String {
        if twoPageMode {
            let start = clampedPageIndex + 1
            let end = min(clampedPageIndex + 2, attachments.count)
            return "\(start)-\(end) / \(attachments.count)"
        }
        return "\(clampedPageIndex + 1) / \(attachments.count)"
    }

    private var canGoBack: Bool {
        clampedPageIndex > 0
    }

    private var canGoForward: Bool {
        if twoPageMode {
            return (clampedPageIndex + 2) < attachments.count
        }
        return (clampedPageIndex + 1) < attachments.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Sheet Music")
                    .font(.headline)
                Spacer()
                if attachments.count > 1 {
                    Button(twoPageMode ? "1 Page" : "2 Pages") {
                        twoPageMode.toggle()
                        if twoPageMode {
                            pageIndex = (clampedPageIndex / 2) * 2
                        }
                    }
                    .buttonStyle(.bordered)
                }
                Text("Page \(pageLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                if twoPageMode {
                    let paneWidth = max(0, (proxy.size.width - 6) * 0.5)
                    HStack(spacing: 6) {
                        SongFullscreenAttachmentPage(
                            attachment: attachments[clampedPageIndex],
                            refreshToken: refreshToken
                        )
                        .frame(width: paneWidth, height: proxy.size.height)
                        .clipped()

                        if let rightPageIndex {
                            SongFullscreenAttachmentPage(
                                attachment: attachments[rightPageIndex],
                                refreshToken: refreshToken
                            )
                            .frame(width: paneWidth, height: proxy.size.height)
                            .clipped()
                        } else {
                            Color.black.opacity(0.92)
                                .frame(width: paneWidth, height: proxy.size.height)
                        }
                    }
                } else {
                    SongFullscreenAttachmentPage(
                        attachment: attachments[clampedPageIndex],
                        refreshToken: refreshToken
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .clipped()

            HStack(spacing: 10) {
                Button {
                    stepBack()
                } label: {
                    Label("Back", systemImage: "chevron.backward")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!canGoBack)

                Button {
                    onMarkup(clampedPageIndex)
                } label: {
                    Label("Markup", systemImage: "pencil.tip")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    stepForward()
                } label: {
                    Label("Next", systemImage: "chevron.forward")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!canGoForward)
            }
        }
    }

    private func stepBack() {
        guard canGoBack else { return }
        let step = twoPageMode ? 2 : 1
        pageIndex = max(0, clampedPageIndex - step)
    }

    private func stepForward() {
        guard canGoForward else { return }
        let step = twoPageMode ? 2 : 1
        pageIndex = min(attachments.count - 1, clampedPageIndex + step)
    }
}

private struct SongAttachmentPreviewCard: View {
    let attachment: SongAttachment
    @State private var previewImage: UIImage?
    @State private var isLoading = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.07))

            if let previewImage {
                Image(uiImage: previewImage)
                    .resizable()
                    .scaledToFit()
                    .padding(8)
            } else if isLoading {
                ProgressView()
                    .tint(.white)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: attachment.kind == .pdf ? "doc.richtext" : "photo")
                        .font(.title2)
                    Text(attachment.originalFileName)
                        .font(.caption)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onAppear {
            loadPreview(force: true)
        }
        .onChange(of: attachment.path) { _, _ in
            loadPreview(force: true)
        }
    }

    private func loadPreview(force: Bool = false) {
        if force {
            previewImage = nil
        } else if previewImage != nil {
            return
        }
        guard let url = attachment.resolvedURL else { return }
        isLoading = true

        previewImage = fallbackPreviewImage(for: url)
        isLoading = false
    }

    private func fallbackPreviewImage(for url: URL) -> UIImage? {
        switch attachment.kind {
        case .image:
            return UIImage(contentsOfFile: url.path)
        case .pdf:
            guard
                let document = PDFDocument(url: url),
                let firstPage = document.page(at: 0)
            else { return nil }
            return firstPage.thumbnail(of: CGSize(width: 1200, height: 1600), for: .mediaBox)
        }
    }
}

private struct SongMediaFullscreenReader: View {
    @Environment(\.dismiss) private var dismiss
    let song: Song
    let initialAttachmentIndex: Int

    @State private var selectedIndex = 0
    @State private var refreshToken = UUID()
    @State private var markupSession: SongMarkupSession?

    private var attachments: [SongAttachment] {
        song.mediaAttachments
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if attachments.isEmpty {
                ContentUnavailableView("No sheet music", systemImage: "doc")
            } else {
                TabView(selection: $selectedIndex) {
                    ForEach(Array(attachments.enumerated()), id: \.element.id) { index, attachment in
                        SongFullscreenAttachmentPage(
                            attachment: attachment,
                            refreshToken: refreshToken
                        )
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                Button {
                    dismiss()
                } label: {
                    Label("Done", systemImage: "chevron.down")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)

                Spacer()

                if attachments.indices.contains(selectedIndex) {
                    Text("\(selectedIndex + 1) / \(attachments.count)")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                }

                Spacer()

                if attachments.indices.contains(selectedIndex),
                   attachments[selectedIndex].resolvedURL != nil {
                    Button {
                        markupSession = SongMarkupSession(initialIndex: selectedIndex)
                    } label: {
                        Label("Markup", systemImage: "pencil.tip")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .padding(.bottom, 8)
            .background(.ultraThinMaterial)
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .sheet(item: $markupSession) { session in
            SongMarkupEditorSheet(
                attachments: attachments,
                initialIndex: session.initialIndex
            ) {
                refreshToken = UUID()
            }
        }
        .onAppear {
            guard !attachments.isEmpty else { return }
            selectedIndex = min(max(0, initialAttachmentIndex), attachments.count - 1)
        }
    }
}

private struct SongMarkupSession: Identifiable, Hashable {
    let id = UUID()
    let initialIndex: Int
}

private struct SongMarkupEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let attachments: [SongAttachment]
    let initialIndex: Int
    var onFinished: () -> Void

    var body: some View {
        SongQuickLookMarkupController(
            attachments: attachments,
            initialIndex: initialIndex
        ) {
            onFinished()
            dismiss()
        }
        .ignoresSafeArea()
    }
}

private struct SongQuickLookMarkupController: UIViewControllerRepresentable {
    let attachments: [SongAttachment]
    let initialIndex: Int
    var onClose: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UINavigationController {
        let previewController = QLPreviewController()
        previewController.dataSource = context.coordinator
        previewController.delegate = context.coordinator
        previewController.currentPreviewItemIndex = context.coordinator.clampedInitialIndex
        previewController.navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: context.coordinator,
            action: #selector(Coordinator.closePressed)
        )
        context.coordinator.previewController = previewController
        return UINavigationController(rootViewController: previewController)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
        context.coordinator.parent = self
        context.coordinator.previewController?.reloadData()
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource, @preconcurrency QLPreviewControllerDelegate {
        var parent: SongQuickLookMarkupController
        weak var previewController: QLPreviewController?
        private var didRequestClose = false

        init(parent: SongQuickLookMarkupController) {
            self.parent = parent
        }

        var previewURLs: [URL] {
            parent.attachments.compactMap(\.resolvedURL)
        }

        var clampedInitialIndex: Int {
            min(max(0, parent.initialIndex), max(0, previewURLs.count - 1))
        }

        @objc
        func closePressed() {
            closeIfNeeded()
        }

        private func closeIfNeeded() {
            guard !didRequestClose else { return }
            didRequestClose = true
            parent.onClose()
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            previewURLs.count
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            previewURLs[index] as NSURL
        }

        func previewControllerWillDismiss(_ controller: QLPreviewController) {
            closeIfNeeded()
        }

        func previewController(
            _ controller: QLPreviewController,
            editingModeFor previewItem: QLPreviewItem
        ) -> QLPreviewItemEditingMode {
            .updateContents
        }
    }
}

private struct SongFullscreenAttachmentPage: View {
    let attachment: SongAttachment
    let refreshToken: UUID
    @State private var image: UIImage?

    var body: some View {
        Group {
            switch attachment.kind {
            case .pdf:
                if let url = attachment.resolvedURL {
                    SongFullscreenPDFView(url: url, refreshToken: refreshToken)
                } else {
                    SongFullscreenUnavailableView(fileName: attachment.originalFileName)
                }
            case .image:
                if let image {
                    GeometryReader { proxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(width: proxy.size.width)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    ProgressView()
                        .tint(.white)
                        .task {
                            loadImage()
                        }
                }
            }
        }
        .onChange(of: refreshToken) { _, _ in
            if attachment.kind == .image {
                image = nil
                loadImage()
            }
        }
    }

    private func loadImage() {
        guard image == nil else { return }
        guard let url = attachment.resolvedURL else { return }
        image = UIImage(contentsOfFile: url.path)
    }
}

private struct SongFullscreenUnavailableView: View {
    let fileName: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
            Text("Unable to load \(fileName)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

private struct SongFullscreenPDFView: UIViewRepresentable {
    let url: URL
    let refreshToken: UUID

    final class Coordinator {
        var loadedURL: URL?
        var loadedToken: UUID?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .black
        view.displaysPageBreaks = false
        view.usePageViewController(false, withViewOptions: nil)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        let shouldReload = context.coordinator.loadedURL != url || context.coordinator.loadedToken != refreshToken
        guard shouldReload else { return }

        context.coordinator.loadedURL = url
        context.coordinator.loadedToken = refreshToken
        uiView.document = PDFDocument(url: url)
        uiView.autoScales = true
        uiView.goToFirstPage(nil)
    }
}
