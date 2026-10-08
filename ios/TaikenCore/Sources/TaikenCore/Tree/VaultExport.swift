import Foundation

/// 技の樹と体験帳を、Markdown のフォルダ (Obsidian などで開ける保管庫) として書き出す。
/// 要素ごとに1ページ、技ごとに1ページ、記した日ごとに1ページ。つながりは [[ ]] のリンクになるので、
/// グラフ表示にすると、根から伸びる技と、それを育てた日々がつながって見える。
/// まだ霧の中の技と、閃いていない閃きは書き出さない (名前を明かさない)。
public enum VaultExporter {
    public struct File: Sendable, Equatable {
        /// 保管庫の中のパス (例: 技/遠目.md)
        public let path: String
        public let contents: String
    }

    public static let folderName = "技の樹"

    public static func files(tree: ExperienceTree, entries: [HistoryEntry], exportedAt: Date, calendar: Calendar = .current) -> [File] {
        let skills = tree.nodes.filter { !$0.isRoot && tree.state(of: $0.id) != .unknown }
        var names: [String: String] = [:]
        var used = Set(tree.elements.map { fileName($0.label) })
        for node in skills {
            var name = fileName(node.title)
            if used.contains(name) { name = "\(name) (\(node.id))" }
            used.insert(name)
            names[node.id] = name
        }
        for element in tree.elements { names[ExperienceTree.rootID(element.id)] = fileName(element.label) }
        func link(_ id: String) -> String? { names[id].map { "[[\($0)]]" } }

        var files: [File] = []
        let lived = entries.filter { $0.status == .completed }.sorted { $0.createdAt < $1.createdAt }

        // はじめに
        var intro = [
            "# \(folderName)",
            "",
            "「体験」から書き出した、技の樹です。要素ごとのページ、技ごとのページ、記した日ごとのページがあります。",
            "記した体験が触れた要素に経験として積もり、段が上がるたびに芽が出て、自分で選んだ技へ伸ばしてきました。",
            "",
            "## 要素",
        ]
        for element in tree.elements {
            let progress = tree.progress(of: element.id)
            intro.append("- [[\(fileName(element.label))]] — \(Ranks.label(progress.rank)) · 経験 \(progress.experience)")
        }
        intro.append("")
        intro.append("年輪: \(tree.totalRank)")
        intro.append("書き出した日: \(dayString(exportedAt, calendar: calendar))")
        files.append(File(path: "はじめに.md", contents: intro.joined(separator: "\n") + "\n"))

        // 要素
        for element in tree.elements {
            let progress = tree.progress(of: element.id)
            var lines = [
                "---",
                "kind: element",
                "glyph: \(element.glyph)",
                "rank: \(progress.rank)",
                "experience: \(progress.experience)",
                "sprouts: \(progress.sprouts)",
                "---",
                "# \(element.label)（\(element.glyph)）",
                "",
                element.hint,
                "",
                "段: \(Ranks.label(progress.rank)) · 経験 \(progress.experience) · 次の段まで \(progress.remaining)",
                "",
                "## この要素の技",
            ]
            for node in tree.nodes(inElement: element.id) where tree.state(of: node.id) != .unknown {
                lines.append("- \(link(node.id) ?? node.title)\(stateSuffix(tree, node))")
            }
            files.append(File(path: "要素/\(fileName(element.label)).md", contents: lines.joined(separator: "\n") + "\n"))
        }

        // 技
        for node in skills {
            let state = tree.state(of: node.id)
            let labels = node.elements.compactMap { tree.element($0)?.label }
            var lines = [
                "---",
                "id: \(node.id)",
                "kind: \(node.kind.rawValue)",
                "elements: [\(labels.joined(separator: ", "))]",
                "state: \(state.rawValue)",
            ]
            if let mastery = tree.mastery(of: node.id) { lines.append("mastery: \(mastery.glyph)") }
            if let date = tree.learnedAt(node.id) { lines.append("learned: \(dayString(date, calendar: calendar))") }
            lines += ["---", "# \(node.title)", ""]
            if !node.reading.isEmpty, node.reading != node.title {
                lines.append("（\(node.reading)）")
                lines.append("")
            }
            lines.append("> \(node.ability)")
            lines.append("")
            if let kind = node.kindLabel {
                lines.append("種類: \(kind)")
            }
            lines.append("要素: " + node.elements.compactMap { tree.element($0).map { "[[\(fileName($0.label))]]" } }.joined(separator: " · "))
            lines.append("")
            if node.kind == .flash, let found = node.found {
                lines.append("閃いたとき: \(found)")
                lines.append("")
            }
            if state != .learned, let requirement = tree.requirement(of: node.id) {
                lines.append("届く条件: \(requirement.sentence)")
                lines.append("")
            }
            let practices = node.practice.compactMap { tree.content.experience($0) }
            if !practices.isEmpty || node.practiceText != nil {
                lines.append("## 稽古")
                if let own = node.practiceText { lines.append("- \(own)") }
                for item in practices { lines.append("- \(item.title) — \(item.invitation)") }
                lines.append("")
            }
            let from = tree.incoming(to: node.id).compactMap { link($0.from) }
            if !from.isEmpty {
                lines.append("ここから: " + from.joined(separator: " · "))
                lines.append("")
            }
            let next = tree.outgoing(from: node.id).compactMap { edge -> String? in
                guard let target = link(edge.to) else { return nil }
                return "- \(edge.kind.label) → \(target)"
            }
            if !next.isEmpty {
                lines.append("## ここから伸びる")
                lines += next
                lines.append("")
            }
            let ties = tree.ties(of: node.id)
            if !ties.isEmpty {
                lines.append("## 結んだ技")
                for tie in ties {
                    let other = tie.from == node.id ? tie.to : tie.from
                    lines.append("- \(link(other) ?? other)" + (tie.note.map { " — \($0)" } ?? ""))
                }
                lines.append("")
            }
            if let life = tree.life(of: node.id), !life.entries.isEmpty {
                lines.append("## この技とともにあった体験")
                for entry in life.entries {
                    var line = "- [[\(dayString(entry.createdAt, calendar: calendar))]] \(entry.title)"
                    if let note = entry.note { line += " ·「\(note)」" }
                    lines.append(line)
                }
                lines.append("")
            }
            files.append(File(path: "技/\(names[node.id] ?? fileName(node.title)).md", contents: lines.joined(separator: "\n")))
        }

        // 記した日
        var byDay: [String: [HistoryEntry]] = [:]
        for entry in lived {
            byDay[dayString(entry.createdAt, calendar: calendar), default: []].append(entry)
        }
        for day in byDay.keys.sorted() {
            var lines = ["# \(day)", ""]
            for entry in byDay[day] ?? [] {
                var line = "- \(timeString(entry.createdAt, calendar: calendar)) \(entry.title)"
                let elements = entry.resolvedElements(content: tree.content).compactMap { tree.element($0) }
                if !elements.isEmpty { line += " — " + elements.map { "[[\(fileName($0.label))]]" }.joined(separator: " ") }
                let grown = tree.skills(usedIn: entry.id).compactMap { link($0.id) }
                if !grown.isEmpty { line += " · 技: " + grown.joined(separator: " ") }
                if let rating = entry.rating { line += " · \(rating.label)" }
                if let note = entry.note { line += " ·「\(note)」" }
                lines.append(line)
            }
            files.append(File(path: "体験帳/\(day).md", contents: lines.joined(separator: "\n") + "\n"))
        }
        return files
    }

    /// ファイル名に使えない文字を除く
    public static func fileName(_ title: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|#^[]\n\r\t")
        let cleaned = title.unicodeScalars.map { forbidden.contains($0) ? "・" : String($0) }.joined()
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        return trimmed.isEmpty ? "無題" : String(trimmed.prefix(60))
    }

    /// フォルダに書き出す (アプリ層でまとめて共有する)
    public static func write(_ files: [File], to directory: URL) throws {
        let manager = FileManager.default
        try? manager.removeItem(at: directory)
        for file in files {
            let url = directory.appendingPathComponent(file.path)
            try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(file.contents.utf8).write(to: url, options: .atomic)
        }
    }

    static func stateSuffix(_ tree: ExperienceTree, _ node: TreeNode) -> String {
        switch tree.state(of: node.id) {
        case .learned: tree.mastery(of: node.id).map { " — 身についた (\($0.glyph))" } ?? " — 身についた"
        case .ready: " — 育てられる"
        case .sensed: " — 気配"
        case .unknown: ""
        }
    }

    static func dayString(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func timeString(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}
