import SwiftUI

/// 印。体験帳に記した体験に押される、朱の印。
/// - 朱文 (outlined): 朱の枠と文字。一覧や小さな場所に
/// - 白文 (filled): 朱の地に白抜きの文字。押した瞬間など、いちばん大事な場所に
/// 少しだけ欠けた朱肉のかすれを付けて、画面の中の「物」に見せる。
struct SealView: View {
    enum Style { case outlined, filled, ghost }

    let character: String
    var size: CGFloat = 40
    var style: Style = .outlined
    var rotation: Double = -4
    var color: Color = Palette.shu

    var body: some View {
        ZStack {
            switch style {
            case .filled:
                RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                    .fill(color)
                Text(character)
                    .font(Typeface.fixedMincho(size * 0.58))
                    .foregroundStyle(Palette.onShu)
            case .outlined:
                RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                    .strokeBorder(color, lineWidth: max(1.5, size * 0.075))
                Text(character)
                    .font(Typeface.fixedMincho(size * 0.58))
                    .foregroundStyle(color)
            case .ghost:
                RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                    .strokeBorder(Palette.line, lineWidth: 1)
                Text(character)
                    .font(Typeface.fixedMincho(size * 0.5, bold: false))
                    .foregroundStyle(Palette.ink3)
            }
        }
        .frame(width: size, height: size)
        .mask {
            if style == .ghost {
                Rectangle()
            } else {
                InkGrain(seed: Self.seed(for: character), size: size)
            }
        }
        .rotationEffect(.degrees(rotation))
        .accessibilityHidden(true)
    }

    /// 同じ文字の印は、いつも同じかすれ方になる
    static func seed(for character: String) -> UInt64 {
        character.unicodeScalars.reduce(UInt64(1_469_598_103)) { ($0 &* 31) &+ UInt64($1.value) }
    }
}

/// 朱肉のかすれ。マスクとして使い、小さな点だけを透明にする
struct InkGrain: View {
    let seed: UInt64
    let size: CGFloat

    var body: some View {
        Canvas { context, canvasSize in
            context.fill(Path(CGRect(origin: .zero, size: canvasSize)), with: .color(.white))
            var random = SeededRandom(seed: seed)
            context.blendMode = .clear
            let count = Int(max(6, size * 0.9))
            for _ in 0..<count {
                let radius = CGFloat(random.next(in: 0.004...0.022)) * canvasSize.width
                let x = CGFloat(random.next(in: 0...1)) * canvasSize.width
                let y = CGFloat(random.next(in: 0...1)) * canvasSize.height
                context.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)), with: .color(.white))
            }
        }
        .frame(width: size, height: size)
    }
}

/// 決まった順番で値を返す乱数 (同じ seed なら同じ模様)
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func nextUInt64() -> UInt64 {
        // SplitMix64
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func next(in range: ClosedRange<Double>) -> Double {
        let unit = Double(nextUInt64() >> 11) / Double(1 << 53)
        return range.lowerBound + (range.upperBound - range.lowerBound) * unit
    }
}

/// 七十二候の短冊。漢字を縦に並べる (候の名前は漢字だけなので、回転の要る文字は無い)
struct TanzakuView: View {
    let text: String
    var size: CGFloat = 22
    var foreground: Color
    var border: Color

    var body: some View {
        VStack(spacing: size * 0.18) {
            ForEach(Array(text.enumerated()), id: \.offset) { item in
                Text(String(item.element))
                    .font(Typeface.fixedMincho(size))
            }
        }
        .foregroundStyle(foreground)
        .padding(.vertical, size * 0.5)
        .padding(.horizontal, size * 0.36)
        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(border, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}
