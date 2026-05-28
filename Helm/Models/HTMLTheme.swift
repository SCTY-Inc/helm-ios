import Foundation

/// HTML escaping helpers and the styled document shell used by the markdown reader.
/// The stylesheet is intentionally restrained: system fonts, generous spacing, and
/// a palette that adapts to light and dark mode via `prefers-color-scheme`.
enum HTMLTheme {
    static func escape(_ string: String) -> String {
        var result = ""
        result.reserveCapacity(string.count)
        for character in string {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            default: result.append(character)
            }
        }
        return result
    }

    static func escapeAttribute(_ string: String) -> String {
        escape(string)
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    static func slug(for text: String) -> String {
        let lowered = text.lowercased()
        let allowed = lowered.map { character -> Character in
            if character.isLetter || character.isNumber {
                return character
            }
            return "-"
        }
        let collapsed = String(allowed)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return collapsed.isEmpty ? "section" : collapsed
    }

    static func wrap(body: String, title: String?) -> String {
        let heading = title.map { "<h1 class=\"doc-title\">\(escape($0))</h1>\n" } ?? ""
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, viewport-fit=cover">
        <style>\(stylesheet)</style>
        </head>
        <body>
        <main class="prose">
        \(heading)\(body)
        </main>
        </body>
        </html>
        """
    }

    private static let stylesheet = """
    :root {
      color-scheme: light dark;
      --bg: #ffffff;
      --fg: #1c1c1e;
      --muted: #6b6b70;
      --rule: rgba(60, 60, 67, 0.12);
      --accent: #0a84ff;
      --code-bg: #f5f5f7;
      --code-fg: #1c1c1e;
      --quote-bar: rgba(60, 60, 67, 0.22);
      --mark: rgba(255, 214, 10, 0.28);
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --bg: #000000;
        --fg: #f2f2f7;
        --muted: #98989f;
        --rule: rgba(235, 235, 245, 0.14);
        --accent: #409cff;
        --code-bg: #1c1c1e;
        --code-fg: #f2f2f7;
        --quote-bar: rgba(235, 235, 245, 0.26);
        --mark: rgba(255, 214, 10, 0.22);
      }
    }
    * { box-sizing: border-box; }
    html { -webkit-text-size-adjust: 100%; }
    body {
      margin: 0;
      background: var(--bg);
      color: var(--fg);
      font: 17px/1.65 -apple-system, "SF Pro Text", system-ui, sans-serif;
      font-feature-settings: "kern", "liga", "calt";
      -webkit-font-smoothing: antialiased;
    }
    .prose {
      max-width: 720px;
      margin: 0 auto;
      padding: 24px 20px 96px;
    }
    .doc-title {
      font-size: 2em;
      letter-spacing: -0.02em;
      margin: 0 0 0.6em;
    }
    h1, h2, h3, h4, h5, h6 {
      font-weight: 700;
      line-height: 1.25;
      letter-spacing: -0.018em;
      margin: 1.8em 0 0.55em;
    }
    h1 { font-size: 1.8em; }
    h2 { font-size: 1.45em; padding-bottom: 0.25em; border-bottom: 1px solid var(--rule); }
    h3 { font-size: 1.2em; }
    h4 { font-size: 1.05em; }
    h5, h6 { font-size: 0.95em; color: var(--muted); }
    p { margin: 0 0 1.1em; }
    a { color: var(--accent); text-decoration: none; }
    a:hover { text-decoration: underline; }
    strong { font-weight: 700; }
    ul, ol { margin: 0 0 1.1em; padding-left: 1.4em; }
    li { margin: 0.3em 0; }
    li.task { list-style: none; margin-left: -1.4em; padding-left: 0; }
    li.task input { margin-right: 0.5em; }
    blockquote {
      margin: 0 0 1.2em;
      padding: 0.2em 0 0.2em 1.1em;
      border-left: 3px solid var(--quote-bar);
      color: var(--muted);
    }
    blockquote p:last-child { margin-bottom: 0; }
    code {
      font: 0.86em/1.5 ui-monospace, "SF Mono", Menlo, monospace;
      background: var(--code-bg);
      padding: 0.15em 0.4em;
      border-radius: 5px;
    }
    pre {
      background: var(--code-bg);
      color: var(--code-fg);
      padding: 14px 16px;
      border-radius: 12px;
      overflow-x: auto;
      margin: 0 0 1.3em;
      -webkit-overflow-scrolling: touch;
    }
    pre code { background: none; padding: 0; font-size: 0.85em; line-height: 1.55; }
    hr { border: none; border-top: 1px solid var(--rule); margin: 2.2em 0; }
    img { max-width: 100%; height: auto; border-radius: 10px; }
    table {
      border-collapse: collapse;
      width: 100%;
      margin: 0 0 1.3em;
      font-size: 0.95em;
    }
    th, td { padding: 0.5em 0.8em; text-align: left; border-bottom: 1px solid var(--rule); }
    th { font-weight: 600; }
    tbody tr:last-child td { border-bottom: none; }
    mark { background: var(--mark); border-radius: 3px; padding: 0 0.15em; }
    """
}
