import Foundation

/// 危険な提案と、強い苦痛のサインの機械的な確認 (Backend の safety.ts と同じパターン)。
/// 端末内で生成する提案 (Apple Intelligence) にもサーバーと同じ最終防衛線をかけるために使う。
public enum SafetyCheck {
    static let riskPatterns: [(pattern: String, label: String)] = [
        ("徹夜|寝ないで|睡眠を削|夜更かしして", "睡眠を削る"),
        ("断食|絶食|(食事|朝食|昼食|夕食|朝ごはん|昼ごはん|晩ごはん|ご飯|ごはん)を抜|何も食べず|食べないで", "食事を抜く"),
        ("運転中|運転しながら|歩きスマホ|自転車.{0,6}(片手|スマホ)", "移動中の危険行為"),
        ("飲酒|お酒を飲|酔っ", "飲酒"),
        ("無断で|勝手に入|立入禁止|盗|万引", "違法・迷惑行為"),
        ("線路|屋上の端|高い所から|崖", "危険な場所"),
        ("自分を傷つけ|痛みを感じ|限界まで|倒れるまで", "心身への過度な負担"),
    ]

    /// 見逃しを減らすため広めに拾う
    static let carePatterns: [String] = [
        "死にたい|しにたい|死のう|消えたい|きえたい|いなくなりたい|生きていたくない|生きるのがつらい|生きてる意味",
        "自殺|自死|自傷|リスカ|リストカット|首をつ|飛び降り|オーバードーズ|OD(し|する|した)",
        "殺したい|ころしたい",
    ]

    /// 危険な提案なら、その種類を返す
    public static func issue(in experience: Experience) -> String? {
        let body = [experience.title, experience.perspective, experience.invitation, experience.reflectionQuestion ?? ""]
            .joined(separator: " ")
        return riskPatterns.first { matches(body, $0.pattern) }?.label
    }

    /// 直近の発言に強い苦痛のサインがあるか
    public static func needsCare(_ texts: [String]) -> Bool {
        texts.contains { text in carePatterns.contains { matches(text, $0) } }
    }

    static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

/// 強い苦痛のサインがあったときの返答 (Backend の CARE_REPLY と同じ文)。
/// 画面ではこの返答のすぐ下に相談先の案内を表示する
public enum CareMessage {
    public static let reply =
        "話してくれてありがとうございます。とてもつらい気持ちを抱えているのかもしれません。" +
        "ひとりで抱え込まずに、信頼できる人や専門の相談窓口に今の気持ちを話してみてください。下に相談先の案内を表示しています。"
}
