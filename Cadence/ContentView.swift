import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "timer")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Cadence")
                .font(.largeTitle.bold())
            Text("Minimal shell — pomodoro logic coming soon.")
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 380, minHeight: 260)
        .padding(40)
    }
}

#Preview {
    ContentView()
}
