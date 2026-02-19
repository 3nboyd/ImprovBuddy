import SwiftUI

struct TheoryTabView: View {
    var body: some View {
        NavigationStack {
            TheoryLibraryView()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            SettingsView()
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel("Settings")
                    }
                }
        }
    }
}
