import Foundation
import PDFKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
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
    @State private var showingDetailPager = false
    @State private var detailSongID: UUID?
    @State private var showingPDFImport = false
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
            .fullScreenCover(isPresented: $showingDetailPager) {
                SongDetailPagerView(
                    songs: filteredSongs,
                    initialSongID: detailSongID
                ) { selectedSong in
                    detailSongID = selectedSong.id
                    showingDetailPager = false
                }
            }
            .fileImporter(
                isPresented: $showingPDFImport,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: false
            ) { result in
                importSongFromPDF(result)
            }
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
                    showingPDFImport = true
                } label: {
                    Label("Import PDF", systemImage: "doc.richtext")
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
                            detailSongID = song.id
                            showingDetailPager = true
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                editingSong = song
                            } label: {
                                Label("Edit", systemImage: "square.and.pencil")
                            }

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

    private func importSongFromPDF(_ result: Result<[URL], Error>) {
        guard case let .success(urls) = result, let source = urls.first else { return }
        _ = source.startAccessingSecurityScopedResource()
        defer { source.stopAccessingSecurityScopedResource() }

        do {
            guard let destinationFolder = FileManager.default
                .urls(for: .documentDirectory, in: .userDomainMask)
                .first?
                .appendingPathComponent("SongPDFs", isDirectory: true) else {
                importMessage = "PDF import failed: Missing documents directory."
                return
            }

            try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
            let destination = destinationFolder.appendingPathComponent("\(UUID().uuidString)-\(source.lastPathComponent)")
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)

            let metadata = PDFSongMetadataExtractor.extract(from: destination)
            let newSong = Song(
                title: metadata.title,
                composer: metadata.author,
                styleTags: [],
                defaultTempoBPM: 120,
                feel: .swing,
                timeSignatureTop: 4,
                timeSignatureBottom: 4,
                form: [Measure(index: 0, sectionLabel: "A", chordSymbol: "Cmaj7")],
                pdfReferencePath: destination.absoluteString
            )
            modelContext.insert(newSong)
            try? modelContext.save()

            importMessage = "Imported PDF as \"\(metadata.title)\" (\(metadata.source.rawValue))."
            editingSong = newSong
        } catch {
            importMessage = "PDF import failed: \(error.localizedDescription)"
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

private struct SongDetailPagerView: View {
    let songs: [Song]
    let initialSongID: UUID?
    var onClose: (Song) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedIndex = 0

    var body: some View {
        NavigationStack {
            Group {
                if songs.isEmpty {
                    ContentUnavailableView("No songs", systemImage: "music.note.list")
                } else {
                    TabView(selection: $selectedIndex) {
                        ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                            SongDetailPage(song: song)
                                .tag(index)
                                .padding(.bottom, 18)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .always))
                }
            }
            .navigationTitle("Song Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        if songs.indices.contains(selectedIndex) {
                            onClose(songs[selectedIndex])
                        }
                        dismiss()
                    }
                }
            }
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
}

private struct SongDetailPage: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var song: Song

    @State private var isChordFormExpanded = true
    @State private var showingPDFAttachPicker = false
    @State private var pdfAttachMessage = ""

    private let chordGridColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    private var pdfURL: URL? {
        guard let raw = song.pdfReferencePath else { return nil }
        return URL(string: raw)
    }

    private var groupedForm: [SongFormSectionGroup] {
        let ordered = song.flattenedForm
        guard !ordered.isEmpty else { return [] }

        var groups: [SongFormSectionGroup] = []
        var currentMeasures: [Measure] = []
        var currentLabel = "Form"
        var groupIndex = 0

        for measure in ordered {
            let explicitLabel = measure.sectionLabel?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let nextLabel = (explicitLabel?.isEmpty == false ? explicitLabel : nil) ?? currentLabel

            if currentMeasures.isEmpty {
                currentLabel = nextLabel
            } else if nextLabel != currentLabel {
                groups.append(SongFormSectionGroup(id: groupIndex, label: currentLabel, measures: currentMeasures))
                groupIndex += 1
                currentMeasures.removeAll(keepingCapacity: true)
                currentLabel = nextLabel
            }

            currentMeasures.append(measure)
        }

        if !currentMeasures.isEmpty {
            groups.append(SongFormSectionGroup(id: groupIndex, label: currentLabel, measures: currentMeasures))
        }

        return groups
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(song.title)
                        .font(.title2.weight(.bold))
                    if let composer = song.composer, !composer.isEmpty {
                        Text(composer)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text("\(Int(song.defaultTempoBPM)) BPM • \(song.feel.displayName) • \(song.timeSignatureTop)/\(song.timeSignatureBottom)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

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

                VStack(alignment: .leading, spacing: 8) {
                    DisclosureGroup(isExpanded: $isChordFormExpanded) {
                        if groupedForm.isEmpty {
                            Text("No chord form added.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(groupedForm) { group in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(group.label)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)

                                        LazyVGrid(columns: chordGridColumns, alignment: .leading, spacing: 8) {
                                            ForEach(group.measures, id: \.id) { measure in
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text("\(measure.index + 1)")
                                                        .font(.caption2.monospacedDigit())
                                                        .foregroundStyle(.secondary)
                                                    Text(measure.chordSymbol)
                                                        .font(.subheadline.weight(.semibold))
                                                        .lineLimit(1)
                                                        .minimumScaleFactor(0.75)
                                                }
                                                .padding(10)
                                                .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
                                                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.top, 8)
                        }
                    } label: {
                        HStack {
                            Text("Chord Form")
                                .font(.headline)
                            Spacer()
                            Text("\(song.flattenedForm.count) bars")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let pdfURL {
                    SongPDFSwipePreview(url: pdfURL)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            showingPDFAttachPicker = true
                        } label: {
                            Label("Attach a PDF", systemImage: "paperclip")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                        if !pdfAttachMessage.isEmpty {
                            Text(pdfAttachMessage)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 12)
        }
        .fileImporter(
            isPresented: $showingPDFAttachPicker,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            attachPDF(result)
        }
    }

    private func attachPDF(_ result: Result<[URL], Error>) {
        guard case let .success(urls) = result, let source = urls.first else { return }

        guard let destinationFolder = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("SongPDFs", isDirectory: true) else {
            pdfAttachMessage = "PDF attach failed: Missing documents directory."
            return
        }

        do {
            try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
            let destination = destinationFolder.appendingPathComponent("\(UUID().uuidString)-\(source.lastPathComponent)")

            _ = source.startAccessingSecurityScopedResource()
            defer { source.stopAccessingSecurityScopedResource() }

            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }

            try FileManager.default.copyItem(at: source, to: destination)

            song.pdfReferencePath = destination.absoluteString
            song.touch()
            try? modelContext.save()
            pdfAttachMessage = ""
        } catch {
            pdfAttachMessage = "PDF attach failed: \(error.localizedDescription)"
        }
    }
}

private struct SongFormSectionGroup: Identifiable {
    let id: Int
    let label: String
    let measures: [Measure]
}

private struct SongPDFSwipePreview: View {
    let url: URL

    @State private var pageImages: [UIImage] = []
    @State private var pageIndex = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Chart PDF")
                    .font(.headline)
                Spacer()
                if !pageImages.isEmpty {
                    Text("Page \(pageIndex + 1)/\(pageImages.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if pageImages.isEmpty {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 260)
                    .overlay {
                        Text("Unable to preview PDF")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
            } else {
                TabView(selection: $pageIndex) {
                    ForEach(Array(pageImages.enumerated()), id: \.offset) { index, image in
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.black.opacity(0.35))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .padding(.horizontal, 2)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 260)
            }
        }
        .onAppear(perform: loadPages)
    }

    private func loadPages() {
        guard let document = PDFDocument(url: url) else {
            pageImages = []
            return
        }

        var images: [UIImage] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            images.append(page.thumbnail(of: CGSize(width: 1000, height: 1400), for: .mediaBox))
        }
        pageImages = images
        pageIndex = 0
    }
}
