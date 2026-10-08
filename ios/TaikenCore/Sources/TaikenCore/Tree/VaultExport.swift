import Foundation

/// 体験の樹と体験帳を、Markdown のフォルダ (Obsidian などで開ける保管庫) として書き出す。
/// 体験ごとに1ページ、要素ごとに1ページ、記した日ごとに1ページ。つながりは [[ ]] のリンクになるので、
/// グラフ表示にすると、この樹がそのまま現れる。
public enum VaultExporter {
    public struct File: Sendable, Equatable {
        /// 保管庫の中のパス (例: 体験/ひと口目の観察.md)
        public let path: String
        public let contents: String
    }

    public static let folderName = "体験の樹"

    public static func files(tree: ExperienceTree, exportedAt: Date, calendar: Calendar = .current) -> [File] {
        var names: [String: String] = [:]
        var used = Set<String>()
        for node in tree.nodes {
            var name = fileName(node.title)
            if used.contains(name) { name = "\(name) (\(node.id))" }
            used.insert(name)
            names[node.id] = name
        }
        func link(_ id: String) -> String {
            names[id].map { "[[\($0)]]" } ?? id
        }

        var files: [File] = []

        // はじめに
        var intro = [
            "# \(folderName)",
            "",
            "「体験」から書き出した、体験の樹です。体験ごとのページ、要素ごとのページ、記した日ごとのページがあります。",
            "グラフ表示にすると、根から伸びる枝と、自分で結んだ糸が見えます。",
            "",
            "## 要素",
        ]
        for element in tree.elements {
            intro.append("- [[\(element.label)]] — \(element.hint)")
        }
        intro.append("")
        intro.append("書き出した日: \(dayString(exportedAt, calendar: calendar))")
        files.append(File(path: "はじめに.md", contents: intro.joined(separator: "\n") + "\n"))

        // 要素
        for element in tree.elements {
            var lines = [
                "---",
                "kind: element",
                "glyph: \(element.glyph)",
                "---",
                "# \(element.label)（\(element.glyph)）",
                "",
                element.hint,
                "",
            ]
            if let root = tree.root(of: element.id) {
                lines.append("根: \(link(root.id))")
                lines.append("")
            }
            lines.append("## この要素の体験")
            for node in tree.nodes(inElement: element.id) {
                lines.append("- \(link(node.id))\(stateSuffix(tree.state(of: node.id)))")
            }
            files.append(File(path: "要素/\(fileName(element.label)).md", contents: lines.joined(separator: "\n") + "\n"))
        }

        // 体験
        for node in tree.nodes {
            let state = tree.state(of: node.id)
            let life = tree.lives[node.id]
            let labels = node.elements.compactMap { tree.element($0)?.label }
            var lines = [
                "---",
                "id: \(node.id)",
                "kind: \(node.kind.rawValue)",
                "elements: [\(labels.joined(separator: ", "))]",
                "state: \(state.rawValue)",
                "lived: \(life?.litCount ?? 0)",
                "---",
                "# \(node.title)",
                "",
                "> \(node.invitation)",
                "",
            ]
            if !node.perspective.isEmpty {
                lines.append(node.perspective)
                lines.append("")
            }
            if let question = node.reflectionQuestion {
                lines.append("問い: \(question)")
                lines.append("")
            }
            lines.append("要素: " + node.elements.compactMap { tree.element($0).map { "[[\($0.label)]]" } }.joined(separator: " · "))
            lines.append("")
            let outgoing = tree.outgoing(from: node.id)
            if !outgoing.isEmpty {
                lines.append("## ここからひらく")
                for edge in outgoing {
                    lines.append("- \(edge.kind.label) → \(link(edge.to))")
                }
                lines.append("")
            }
            let ties = tree.ties(of: node.id)
            if !ties.isEmpty {
                lines.append("## 結んだ体験")
                for tie in ties {
                    let other = tie.from == node.id ? tie.to : tie.from
                    lines.append("- \(link(other))" + (tie.note.map { " — \($0)" } ?? ""))
                }
                lines.append("")
            }
            if let life, !life.entries.isEmpty {
                lines.append("## 記録")
                for entry in life.entries {
                    var line = "- [[\(dayString(entry.createdAt, calendar: calendar))]]"
                    if entry.status == .active { line += " 体験中" }
                    if let rating = entry.rating { line += " · \(rating.label)" }
                    if let note = entry.note { line += " ·「\(note)」" }
                    lines.append(line)
                }
                lines.append("")
            }
            files.append(File(path: "体験/\(names[node.id] ?? fileName(node.title)).md", contents: lines.joined(separator: "\n")))
        }

        // 記した日
        var byDay: [String: [(HistoryEntry, String)]] = [:]
        for (id, life) in tree.lives {
            for entry in life.entries {
                byDay[dayString(entry.createdAt, calendar: calendar), default: []].append((entry, id))
            }
        }
        for day in byDay.keys.sorted() {
            let items = (byDay[day] ?? []).sorted { $0.0.createdAt < $1.0.createdAt }
            var lines = ["# \(day)", ""]
            for (entry, id) in items {
                var line = "- \(timeString(entry.createdAt, calendar: calendar)) \(link(id))"
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

    static func stateSuffix(_ state: NodeState) -> String {
        switch state {
        case .active: " — 体験中"
        case .lit: " — 灯った"
        case .bud: " — 芽"
        case .quiet: ""
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
