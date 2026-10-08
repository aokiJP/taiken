import SwiftUI
import TaikenCore

/// いまの時刻の空。ゆっくり揺れる光 (視差効果を減らす設定では止まる) と、夜には星。
struct SkyBackground: View {
    let time: TimeOfDay
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let palette = time.sky(dark: colorScheme == .dark)
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                MeshGradient(width: 3, height: 3, points: Self.points(at: t), colors: Self.colors(palette))
                if time.isDark {
                    StarField(seed: 7, time: t)
                }
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 1.4), value: palette)
        .accessibilityHidden(true)
    }

    /// 真ん中の点だけをゆっくり動かし、温かい光の溜まりを漂わせる
    static func points(at t: Double) -> [SIMD2<Float>] {
        let dx = Float(sin(t / 9) * 0.07)
        let dy = Float(cos(t / 13) * 0.05)
        return [
            SIMD2(0, 0), SIMD2(0.5, 0), SIMD2(1, 0),
            SIMD2(0, 0.52), SIMD2(0.42 + dx, 0.6 + dy), SIMD2(1, 0.48),
            SIMD2(0, 1), SIMD2(0.5, 1), SIMD2(1, 1),
        ]
    }

    static func colors(_ p: SkyPalette) -> [Color] {
        [
            p.top, p.top, p.top,
            p.middle, p.bottom, p.middle,
            p.bottom, p.bottom, p.bottom,
        ]
    }
}

/// 夜空の星。決まった位置に置き、明るさだけをゆっくり変える
struct StarField: View {
    let seed: UInt64
    let time: Double

    var body: some View {
        Canvas { context, size in
            var random = SeededRandom(seed: seed)
            for index in 0..<56 {
                let x = CGFloat(random.next(in: 0...1)) * size.width
                let y = CGFloat(random.next(in: 0...0.62)) * size.height
                let radius = CGFloat(random.next(in: 0.4...1.25))
                let base = random.next(in: 0.35...0.9)
                let speed = random.next(in: 0.3...0.9)
                context.opacity = base * (0.75 + 0.25 * sin(time * speed + Double(index)))
                context.fill(
                    Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                    with: .color(.white)
                )
            }
        }
    }
}

// MARK: - 空を子ビューに伝える

private struct SkyPaletteKey: EnvironmentKey {
    static let defaultValue: SkyPalette? = nil
}

extension EnvironmentValues {
    /// いま画面の地になっている空。面の明るさや、空の上の文字の色を決めるのに使う
    var skyPalette: SkyPalette? {
        get { self[SkyPaletteKey.self] }
        set { self[SkyPaletteKey.self] = newValue }
    }
}
