import SwiftUI

/// The website's motion language, brought into the apps: energy that
/// sweeps across headline numbers, haloes that breathe, the fork mark
/// drawing itself, and routes you can watch yourself travel.
///
/// Ornament only — nothing here changes what a number says, and every
/// animation lives inside a small view so it never forces a parent
/// (especially a Map) to redraw.

// MARK: - Energy sweep

/// A band of light travelling across the content, masked to its shape —
/// the site's gradient sweep, on a number.
struct GaitwayShimmer: ViewModifier {
    var period: Double = 3.4

    @State private var phase: CGFloat = -0.6

    func body(content: Content) -> some View {
        content.overlay {
            GeometryReader { geometry in
                let band = max(24, geometry.size.width * 0.45)
                LinearGradient(
                    colors: [.clear, .white.opacity(0.7), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: band)
                .offset(x: phase * (geometry.size.width + band) - band / 2)
                .blendMode(.plusLighter)
            }
            .mask(content)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeInOut(duration: period).repeatForever(autoreverses: false)) {
                    phase = 1.6
                }
            }
        }
    }
}

extension View {
    /// Headline moments only — a shimmer on a mid-run metric would be
    /// noise exactly when it needs to be read.
    func gaitwayShimmer(period: Double = 3.4) -> some View {
        modifier(GaitwayShimmer(period: period))
    }
}

// MARK: - Breathing halo

/// An expanding ring that fades as it grows — the site's node halo.
/// Sits behind whatever it decorates.
struct GaitwayHalo: View {
    var color: Color = Gaitway.cyan
    var period: Double = 2.4

    @State private var expanded = false

    var body: some View {
        Circle()
            .strokeBorder(color.opacity(expanded ? 0 : 0.6), lineWidth: 2)
            .scaleEffect(expanded ? 1.9 : 0.85)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeOut(duration: period).repeatForever(autoreverses: false)) {
                    expanded = true
                }
            }
    }
}

// MARK: - The fork mark

/// The brand's shape: a stem that splits. Stroked with `.trim` so it
/// can draw itself.
struct ForkMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let split = CGPoint(x: rect.midX, y: rect.midY + rect.height * 0.05)
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: split)
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.1, y: rect.minY))
        path.move(to: split)
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.1, y: rect.minY))
        return path
    }
}

/// The fork mark drawing itself on appear — the pop-up's own little
/// arrival animation.
struct AnimatedForkMark: View {
    var color: Color = Gaitway.magenta
    var size: CGFloat = 17

    @State private var drawn = false

    var body: some View {
        ForkMark()
            .trim(from: 0, to: drawn ? 1 : 0)
            .stroke(color, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .gaitwayGlow(color, radius: 6)
            .onAppear {
                withAnimation(.easeOut(duration: 0.5)) { drawn = true }
            }
    }
}

/// The site's section divider: a lit rule that forks at its end.
struct ForkRule: View {
    var width: CGFloat = 56

    var body: some View {
        HStack(spacing: 0) {
            Capsule()
                .fill(LinearGradient(
                    colors: [Color.white.opacity(0.35), Gaitway.cyan],
                    startPoint: .leading,
                    endPoint: .trailing
                ))
                .frame(width: width, height: 2)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Gaitway.cyan)
                    .frame(width: 16, height: 2)
                    .rotationEffect(.degrees(-26), anchor: .leading)
                Capsule()
                    .fill(Gaitway.magenta)
                    .frame(width: 16, height: 2)
                    .rotationEffect(.degrees(26), anchor: .leading)
            }
            .frame(width: 16, height: 16)
        }
        .gaitwayGlow(Gaitway.cyan, radius: 6)
    }
}

// MARK: - Path travel

/// A route as a line you travel: filled behind you, forks as ticks
/// along it, and a glowing dot at your position. Used for a planned
/// route on the watch, and for progress through a single segment.
struct PathTravelTrack: View {
    /// Fractions along the track where forks sit (0…1).
    var stops: [Double] = []
    /// How far along you are (0…1).
    var progress: Double
    var height: CGFloat = 5

    @State private var glowing = false

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let clamped = min(max(progress, 0), 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.12))
                    .frame(height: height)
                Capsule()
                    .fill(Gaitway.gradient)
                    .frame(width: max(height, width * clamped), height: height)
                    .gaitwayGlow(Gaitway.cyan, radius: glowing ? 9 : 3)
                ForEach(Array(stops.enumerated()), id: \.offset) { _, stop in
                    Circle()
                        .fill(Gaitway.background)
                        .overlay(Circle().strokeBorder(Gaitway.cyan.opacity(0.85), lineWidth: 1.5))
                        .frame(width: 7, height: 7)
                        .offset(x: width * min(max(stop, 0), 1) - 3.5)
                }
                Circle()
                    .fill(.white)
                    .frame(width: 9, height: 9)
                    .gaitwayGlow(.white, radius: glowing ? 9 : 4)
                    .offset(x: min(width - 9, max(0, width * clamped - 4.5)))
            }
            .frame(height: 14, alignment: .center)
        }
        .frame(height: 14)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                glowing = true
            }
        }
    }
}

// MARK: - Backdrop

/// The site's dot grid and top glow, behind the phone's lists — depth
/// without anything moving.
struct GaitwayBackdrop: View {
    var body: some View {
        ZStack {
            Gaitway.background
            Canvas { context, size in
                let spacing: CGFloat = 26
                let dot = CGSize(width: 1.6, height: 1.6)
                var y: CGFloat = 0
                while y < size.height {
                    var x: CGFloat = 0
                    while x < size.width {
                        context.fill(
                            Path(ellipseIn: CGRect(origin: CGPoint(x: x, y: y), size: dot)),
                            with: .color(.white.opacity(0.05))
                        )
                        x += spacing
                    }
                    y += spacing
                }
            }
            LinearGradient(
                colors: [Gaitway.cyan.opacity(0.10), .clear],
                startPoint: .top,
                endPoint: .center
            )
        }
        .ignoresSafeArea()
    }
}
