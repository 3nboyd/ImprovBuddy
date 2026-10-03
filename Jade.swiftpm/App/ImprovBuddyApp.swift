import SwiftData
import SwiftUI

@main
struct ImprovBuddyApp: App {
    @StateObject private var appEnvironment = AppEnvironment()
    @StateObject private var services = ServiceContainer()
    @State private var showsLaunchSplash = true
    private let modelContainer = ModelContainerFactory.makeContainer()

    var body: some Scene {
        WindowGroup {
            ZStack {
                if showsLaunchSplash {
                    JadeLaunchSplashView(
                        accentColor: appEnvironment.accentColor,
                        isPresented: $showsLaunchSplash
                    )
                    .zIndex(1000)
                } else {
                    RootTabView()
                        .environmentObject(appEnvironment)
                        .environmentObject(services)
                        .preferredColorScheme(.dark)
                        .tint(appEnvironment.accentColor)
                        .accentColor(appEnvironment.accentColor)
                        .transition(.opacity)
                }
            }
        }
        .modelContainer(modelContainer)
    }
}

private struct JadeLaunchSplashView: View {
    let accentColor: Color
    @Binding var isPresented: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var animateIn = false
    @State private var animateOut = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                    .ignoresSafeArea()

                VStack(spacing: 16) {
                    JadeCrystalMark(accentColor: accentColor)
                        .frame(width: 172, height: 214)
                        .shadow(color: accentColor.opacity(0.72), radius: 24)

                    Text("Jade")
                        .font(.system(size: 42, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)

                    Text("The Live Musician's Best Friend")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(accentColor)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 28)
            }
            .opacity(animateOut ? 0 : (animateIn ? 1 : 0))
            .scaleEffect(animateOut ? 0.74 : (animateIn ? 1 : 0.96))
            .offset(
                x: animateOut ? proxy.size.width * 1.1 : 0,
                y: animateOut ? -proxy.size.height * 0.08 : 0
            )
            .rotationEffect(.degrees(animateOut ? 62 : 0))
            .onAppear {
                runSequence()
            }
        }
        .allowsHitTesting(false)
    }

    private func runSequence() {
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.2)) {
                animateIn = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation(.easeOut(duration: 0.2)) {
                    animateOut = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
                    isPresented = false
                }
            }
            return
        }

        withAnimation(.easeOut(duration: 0.36)) {
            animateIn = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.22) {
            withAnimation(.spring(response: 0.62, dampingFraction: 0.84)) {
                animateOut = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
                isPresented = false
            }
        }
    }
}

private struct JadeCrystalMark: View {
    let accentColor: Color

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height

            let top = CGPoint(x: width * 0.5, y: height * 0.06)
            let upperLeft = CGPoint(x: width * 0.14, y: height * 0.44)
            let upperRight = CGPoint(x: width * 0.86, y: height * 0.44)

            let lowerLeft = CGPoint(x: width * 0.14, y: height * 0.56)
            let lowerRight = CGPoint(x: width * 0.86, y: height * 0.56)
            let bottom = CGPoint(x: width * 0.5, y: height * 0.94)

            let bridgeLeft = CGPoint(x: width * 0.28, y: height * 0.5)
            let bridgeRight = CGPoint(x: width * 0.72, y: height * 0.5)

            let upperLeftFacet = [top, upperLeft, CGPoint(x: width * 0.5, y: height * 0.44)]
            let upperRightFacet = [top, CGPoint(x: width * 0.5, y: height * 0.44), upperRight]
            let lowerLeftFacet = [bottom, lowerLeft, CGPoint(x: width * 0.5, y: height * 0.56)]
            let lowerRightFacet = [bottom, CGPoint(x: width * 0.5, y: height * 0.56), lowerRight]
            let bridgeFacet = [
                CGPoint(x: width * 0.5, y: height * 0.39),
                bridgeLeft,
                CGPoint(x: width * 0.5, y: height * 0.61),
                bridgeRight
            ]

            ZStack {
                polygon([top, upperLeft, upperRight])
                    .stroke(accentColor.opacity(0.95), lineWidth: 4)
                    .blur(radius: 12)

                polygon([bottom, lowerLeft, lowerRight])
                    .stroke(accentColor.opacity(0.95), lineWidth: 4)
                    .blur(radius: 12)

                polygon(upperLeftFacet)
                    .fill(
                        LinearGradient(
                            colors: [accentColor.opacity(0.86), accentColor.opacity(0.45)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                polygon(upperRightFacet)
                    .fill(
                        LinearGradient(
                            colors: [accentColor.opacity(0.66), accentColor.opacity(0.28)],
                            startPoint: .topTrailing,
                            endPoint: .bottomLeading
                        )
                    )

                polygon(lowerLeftFacet)
                    .fill(
                        LinearGradient(
                            colors: [accentColor.opacity(0.58), accentColor.opacity(0.26)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                polygon(lowerRightFacet)
                    .fill(
                        LinearGradient(
                            colors: [accentColor.opacity(0.84), accentColor.opacity(0.42)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                polygon(bridgeFacet)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.88), accentColor.opacity(0.96)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                polygon([top, upperLeft, upperRight])
                    .stroke(Color.white.opacity(0.84), lineWidth: 2)

                polygon([bottom, lowerLeft, lowerRight])
                    .stroke(Color.white.opacity(0.84), lineWidth: 2)

                polygon(bridgeFacet)
                    .stroke(Color.white.opacity(0.9), lineWidth: 2.4)

                Path { path in
                    path.move(to: top)
                    path.addLine(to: bottom)
                }
                .stroke(Color.white.opacity(0.34), lineWidth: 1.6)
            }
        }
    }

    private func polygon(_ points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
            path.closeSubpath()
        }
    }
}
