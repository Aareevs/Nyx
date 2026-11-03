import SwiftUI

/// The Help window's content: a topic sidebar and an article, like a wiki.
struct HelpView: View {
    var onClose: () -> Void
    @State private var selectedID = "welcome"
    @State private var query = ""
    @State private var topics = HelpLibrary.topics()

    private var results: [HelpArticle] { HelpLibrary.search(query) }
    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }
    private var selected: HelpArticle? { topics.flatMap(\.articles).first { $0.id == selectedID } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                sidebar
                    .frame(width: 220)
                Divider()
                articleView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 780, height: 520)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "book.closed.fill").foregroundStyle(.secondary)
            Text("Nyx Help").font(.headline)
            Spacer()
            Button("Done", action: onClose).keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search help", text: $query).textFieldStyle(.plain)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
            .padding(10)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if isSearching {
                        if results.isEmpty {
                            Text("No articles match.").font(.callout).foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                        }
                        ForEach(results) { row($0) }
                    } else {
                        ForEach(topics) { topic in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(topic.title.uppercased())
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 12).padding(.bottom, 2)
                                ForEach(topic.articles) { row($0) }
                            }
                        }
                    }
                }
                .padding(.bottom, 12)
            }
        }
    }

    private func row(_ article: HelpArticle) -> some View {
        Button { selectedID = article.id } label: {
            HStack(spacing: 8) {
                Image(systemName: article.symbol).frame(width: 18).foregroundStyle(.tint)
                Text(article.title).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7)
                .fill(article.id == selectedID ? Color.accentColor.opacity(0.18) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
    }

    @ViewBuilder
    private var articleView: some View {
        if let article = selected {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 12) {
                        Image(systemName: article.symbol).font(.system(size: 26)).foregroundStyle(.tint)
                        Text(article.title).font(.largeTitle.bold())
                    }
                    Text(article.summary).font(.title3).foregroundStyle(.secondary)
                    Divider()
                    ForEach(article.sections, id: \.self) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(section.heading).font(.title3.weight(.semibold))
                            ForEach(section.body, id: \.self) { paragraph in
                                Text(markdown(paragraph)).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text("Pick an article.").foregroundStyle(.secondary)
        }
    }

    private func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}
