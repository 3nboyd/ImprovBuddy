import SwiftData
import SwiftUI

struct SongsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Song.updatedAt, order: .reverse) private var songs: [Song]

    @State private var showingCreateSheet = false
    @State private var selection: Song?

    var body: some View {
        NavigationStack {
            List {
                ForEach(songs) { song in
                    Button {
                        selection = song
                    } label: {
                        SongRow(song: song)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete(perform: deleteSongs)
            }
            .navigationTitle("Songs")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingCreateSheet = true
                    } label: {
                        Label("New Song", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingCreateSheet) {
                SongEditorView(song: nil)
            }
            .sheet(item: $selection) { song in
                SongEditorView(song: song)
            }
        }
    }

    private func deleteSongs(at offsets: IndexSet) {
        offsets.forEach { modelContext.delete(songs[$0]) }
        try? modelContext.save()
    }
}

private struct SongRow: View {
    let song: Song

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(song.title)
                .font(.headline)

            HStack(spacing: 10) {
                Text("\(Int(song.defaultTempoBPM)) BPM")
                Text(song.feel.displayName)
                Text("\(song.timeSignatureTop)/\(song.timeSignatureBottom)")
                if let composer = song.composer, !composer.isEmpty {
                    Text(composer)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
