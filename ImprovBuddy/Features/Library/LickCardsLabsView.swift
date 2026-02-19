import SwiftUI

struct LickCardsLabsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "flask")
                .font(.system(size: 44))
            Text("Lick Cards is in Labs.")
                .font(.headline)
            Text("This stretch module stays hidden by default until the loop extraction workflow is validated.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
        }
        .padding()
        .navigationTitle("Lick Cards")
    }
}
