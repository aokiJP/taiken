import SwiftUI
import TaikenCore
import UIKit

// 見た目の言語「光と印」(docs/DESIGN.md)。アプリとウィジェットの両方で使う。
// - 地は、いまの時刻の空。障子越しの光のような半透明の面に文字を置く
// - 文字は藍墨。朱 (朱肉) は印と、印に値する操作 (やってみる・記す) にだけ使う
// - 誘いかけの文は明朝。操作の文字はシステムのゴシック

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    /// ライト・ダークで値が変わる色
    static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in traits.userInterfaceStyle == .dark ? dark : light })
    }
}

enum Palette {
    /// 朱肉
    static let shu = Color.dynamic(light: UIColor(hex: 0xCC3A2C), dark: UIColor(hex: 0xEC5B4B))
    static let shuSoft = Color.dynamic(light: UIColor(hex: 0xCC3A2C, alpha: 0.10), dark: UIColor(hex: 0xEC5B4B, alpha: 0.16))
    /// 朱の上の文字
    static let onShu = Color(hex: 0xFFF7F3)
    /// 藍墨 (面の上の文字)
    static let ink = Color.dynamic(light: UIColor(hex: 0x1C2131), dark: UIColor(hex: 0xECEEF6))
    static let ink2 = Color.dynamic(light: UIColor(hex: 0x525A70), dark: UIColor(hex: 0xAAB0C4))
    static let ink3 = Color.dynamic(light: UIColor(hex: 0x868CA0), dark: UIColor(hex: 0x7C839A))
    /// 細い線・控えめな面
    static let line = Color.dynamic(light: UIColor(hex: 0x1C2131, alpha: 0.11), dark: UIColor(hex: 0xECEEF6, alpha: 0.13))
    static let wash = Color.dynamic(light: UIColor(hex: 0x1C2131, alpha: 0.05), dark: UIColor(hex: 0xECEEF6, alpha: 0.07))
    /// 半透明の面 (障子)
    static let panel = Color.dynamic(light: UIColor(white: 1, alpha: 0.72), dark: UIColor(hex: 0x171C2F, alpha: 0.62))
    /// 夜の空の上でライト表示のときは、灯りの下の紙のように明るくする
    static let panelLamplight = Color.dynamic(light: UIColor(hex: 0xFBFAF7, alpha: 0.9), dark: UIColor(hex: 0x171C2F, alpha: 0.62))
    /// シート・体験帳の地
    static let paper = Color.dynamic(light: UIColor(hex: 0xF7F8FB), dark: UIColor(hex: 0x1A1F33))
    static let shadow = Color.dynamic(light: UIColor(hex: 0x1C2131, alpha: 0.28), dark: UIColor(white: 0, alpha: 0.55))
}

// MARK: - 空

/// 時間帯ごとの空の色。上・中・下の3色と、その上に置く文字が明るいか
struct SkyPalette: Equatable {
    let top: Color
    let middle: Color
    let bottom: Color
    /// 空が暗い (空の上の文字を明るくする)
    let isDark: Bool

    var onSky: Color { isDark ? Color(hex: 0xF3F1EC) : Color(hex: 0x1C2131) }
    var onSkySecondary: Color { isDark ? Color(hex: 0xF3F1EC, opacity: 0.72) : Color(hex: 0x1C2131, opacity: 0.64) }
    var colors: [Color] { [top, middle, bottom] }
}

extension TimeOfDay {
    func sky(dark: Bool) -> SkyPalette {
        switch (self, dark) {
        case (.dawn, false): SkyPalette(top: Color(hex: 0xC3CDE6), middle: Color(hex: 0xEFD3D6), bottom: Color(hex: 0xFBE6D6), isDark: false)
        case (.morning, false): SkyPalette(top: Color(hex: 0xCBE3F1), middle: Color(hex: 0xE6F1F1), bottom: Color(hex: 0xF8F4EA), isDark: false)
        case (.daytime, false): SkyPalette(top: Color(hex: 0xB9D8EE), middle: Color(hex: 0xE2EFF5), bottom: Color(hex: 0xF6F5EF), isDark: false)
        case (.evening, false): SkyPalette(top: Color(hex: 0x8798C2), middle: Color(hex: 0xEEB39E), bottom: Color(hex: 0xF9DFCB), isDark: false)
        case (.night, false): SkyPalette(top: Color(hex: 0x1A2140), middle: Color(hex: 0x2B3356), bottom: Color(hex: 0x46445F), isDark: true)
        case (.lateNight, false): SkyPalette(top: Color(hex: 0x0E1327), middle: Color(hex: 0x19203E), bottom: Color(hex: 0x252A48), isDark: true)
        case (.dawn, true): SkyPalette(top: Color(hex: 0x1D2238), middle: Color(hex: 0x382C44), bottom: Color(hex: 0x4A3640), isDark: true)
        case (.morning, true): SkyPalette(top: Color(hex: 0x172538), middle: Color(hex: 0x1E2F40), bottom: Color(hex: 0x2A3442), isDark: true)
        case (.daytime, true): SkyPalette(top: Color(hex: 0x14273B), middle: Color(hex: 0x1A3045), bottom: Color(hex: 0x233548), isDark: true)
        case (.evening, true): SkyPalette(top: Color(hex: 0x181D38), middle: Color(hex: 0x3C2A3E), bottom: Color(hex: 0x583A39), isDark: true)
        case (.night, true): SkyPalette(top: Color(hex: 0x0D1225), middle: Color(hex: 0x161F40), bottom: Color(hex: 0x22294B), isDark: true)
        case (.lateNight, true): SkyPalette(top: Color(hex: 0x090D1C), middle: Color(hex: 0x101732), bottom: Color(hex: 0x19203F), isDark: true)
        }
    }
}

/// 動かない空 (ウィジェット・共有カード・プレビュー用)
struct StillSky: View {
    let palette: SkyPalette

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: palette.top, location: 0),
                .init(color: palette.middle, location: 0.58),
                .init(color: palette.bottom, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - 書体

/// 明朝 (ヒラギノ明朝)。誘いかけ・体験の名前・季節の名前に使う。Dynamic Type に合わせて大きさが変わる
enum Typeface {
    static func mincho(_ size: CGFloat, bold: Bool = false, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(bold ? "HiraMinProN-W6" : "HiraMinProN-W3", size: size, relativeTo: style)
    }

    /// 大きさを固定した明朝 (印・短冊など、形として扱う文字)
    static func fixedMincho(_ size: CGFloat, bold: Bool = true) -> Font {
        .custom(bold ? "HiraMinProN-W6" : "HiraMinProN-W3", fixedSize: size)
    }
}

extension Font {
    /// 誘いかけの文 (カードの主役)
    static let invitation = Typeface.mincho(21, relativeTo: .title2)
    /// 振り返りの問い
    static let question = Typeface.mincho(17, relativeTo: .title3)
    /// 体験の名前
    static let experienceTitle = Typeface.mincho(15, bold: true, relativeTo: .headline)
    /// 画面の見出し
    static let displayTitle = Typeface.mincho(30, bold: true, relativeTo: .largeTitle)
    static let sectionTitle = Typeface.mincho(20, bold: true, relativeTo: .title3)
}
