import SwiftUI

/// A shimmering placeholder row, shown while data is loading.
struct LEOSkeletonRow: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4).frame(height: 14)
                RoundedRectangle(cornerRadius: 4).frame(width: 120, height: 10)
            }
            Spacer()
        }
        .foregroundStyle(shimmerGradient)
        .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: phase)
        .onAppear { phase = 1 }
    }

    private var shimmerGradient: LinearGradient {
        LinearGradient(
            colors: [Theme.Color.surface, Theme.Color.surfaceElevated, Theme.Color.surface],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

/// Shows N skeleton rows while `isLoading` is true, otherwise shows content.
struct LEOLoadingContainer<Content: View>: View {
    let isLoading: Bool
    let rowCount: Int
    @ViewBuilder let content: () -> Content

    var body: some View {
        if isLoading {
            VStack(spacing: 12) {
                ForEach(0..<rowCount, id: \.self) { _ in
                    LEOSkeletonRow()
                        .padding(.horizontal)
                }
            }
            .padding(.vertical)
        } else {
            content()
        }
    }
}

/// Offline banner shown at the top of AI-powered surfaces when the device has no network.
struct LEOOfflineBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
            Text("Offline — using on-device AI only")
                .font(.caption.bold())
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.Color.warning)
        .clipShape(Capsule())
    }
}
