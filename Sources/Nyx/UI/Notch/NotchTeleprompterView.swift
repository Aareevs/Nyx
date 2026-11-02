import SwiftUI

struct NotchTeleprompterView: View {
    let size: CGSize
    @Environment(\.notchSettingsPreview) private var preview
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = NotchTeleprompterService.shared
    @AppStorage(DefaultsKey.notchTeleprompterHideFromCaptures) private var hidesFromCaptures = true
    @State private var draft = ""
    /// Pushes the column down a little the moment the line changes, then lets
    /// it settle back, so the new line rises into place instead of appearing.
    @State private var slide: CGFloat = 0
    @State private var editorView: NSTextView?
    private var text: NotchTeleprompterStrings { FeatureStrings.notchTeleprompter(l10n.language) }

    var body: some View {
        Group {
            if service.isEditing {
                editor
            } else if service.hasScript {
                reader
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: service.isEditing) { _, open in
            guard !preview else { return }
            NotchService.shared.setPageLayer(.teleprompter, close: open ? { finishEditing() } : nil)
        }
        .onDisappear {
            guard !preview else { return }
            if service.isEditing { finishEditing() }
            service.pause()
            NotchService.shared.setPageLayer(.teleprompter, close: nil)
        }
    }

    // MARK: Reading

    private var reader: some View {
        VStack(spacing: 8) {
            header
            lineStack
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Measured on the container that fills the page, not on the
                // lines themselves, which only ever take the width of their
                // own words.
                .background(GeometryReader { proxy in
                    Color.clear
                        .onAppear { fitLines(to: proxy.size.width) }
                        .onChange(of: proxy.size.width) { _, width in fitLines(to: width) }
                })
            controls
            progressRow
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(text.title).font(.system(size: 12, weight: .semibold))
            Spacer(minLength: 6)
            Text(String(format: text.lineFormat, service.index + 1, service.lines.count))
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)).monospacedDigit()
            Button { service.cycleSize() } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(String(format: text.resizeFormat, text.sizeName(service.size)))
            .accessibilityLabel(String(format: text.resizeFormat, text.sizeName(service.size)))
            Button {
                hidesFromCaptures.toggle()
                NotchService.shared.refreshCaptureSharing()
            } label: {
                Image(systemName: hidesFromCaptures ? "eye.slash" : "eye")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(hidesFromCaptures ? .white.opacity(0.85) : .white.opacity(0.5))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(hidesFromCaptures ? text.hiddenFromRecordings : text.visibleInRecordings)
            .accessibilityLabel(hidesFromCaptures ? text.hiddenFromRecordings : text.visibleInRecordings)
        }
        .padding(.horizontal, 4)
    }

    /// The line being read, large, between the ones before and after it.
    private var lineStack: some View {
        let lines = service.lines, index = service.index
        func line(_ offset: Int) -> String? {
            lines.indices.contains(index + offset) ? lines[index + offset] : nil
        }
        return VStack(spacing: 7) {
            Text(line(-1) ?? " ").font(.system(size: 12)).foregroundStyle(.white.opacity(0.32))
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5).fill(Color.yellow).frame(width: 3, height: 22)
                Text(line(0) ?? " ").font(.system(size: 19, weight: .bold)).foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
            }
            Text(line(1) ?? " ").font(.system(size: 13)).foregroundStyle(.white.opacity(0.58))
            Text(line(2) ?? " ").font(.system(size: 12)).foregroundStyle(.white.opacity(0.28))
        }
        .lineLimit(1)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 10)
        .contentTransition(.opacity)
        .offset(y: slide)
        .animation(.smooth(duration: 0.45), value: index)
        .onChange(of: index) { old, new in
            let direction: CGFloat = new >= old ? 1 : -1
            slide = 22 * direction
            withAnimation(.smooth(duration: 0.45)) { slide = 0 }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line(0) ?? "")
    }

    /// The width a line can fill: the page less its padding and the yellow
    /// marker with its gap beside the current line.
    private func fitLines(to pageWidth: CGFloat) {
        guard !preview else { return }
        service.setLayoutWidth(pageWidth - 20 - 3 - 8 - 4)
    }

    private var controls: some View {
        HStack(spacing: 6) {
            circleButton("arrow.counterclockwise", text.restart) { service.restart() }
            circleButton("chevron.up", text.previousLine) { service.previousLine() }
            circleButton("chevron.down", text.nextLine) { service.nextLine() }
            playPill
            Spacer(minLength: 6)
            speedStepper
            circleButton("square.and.pencil", text.editScript) { beginEditing() }
        }
    }

    private var playPill: some View {
        Button { service.toggle() } label: {
            HStack(spacing: 6) {
                Image(systemName: service.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 11))
                Text(service.isPlaying ? text.pause : (service.elapsed > 0 ? text.resume : text.start))
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 14).frame(height: 30)
            .fixedSize()
            .background(Color.white, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(service.isPlaying ? text.pause : text.resume)
    }

    private var speedStepper: some View {
        HStack(spacing: 4) {
            stepButton("minus", text.slower) { service.adjustWPM(by: -1) }
            VStack(spacing: 0) {
                Text("\(service.wpm)").font(.system(size: 14, weight: .semibold)).monospacedDigit()
                Text(text.wpm).font(.system(size: 7, weight: .semibold)).foregroundStyle(.white.opacity(0.55))
            }
            .frame(minWidth: 34)
            stepButton("plus", text.faster) { service.adjustWPM(by: 1) }
        }
        .padding(.horizontal, 4).frame(height: 30)
        .background(.white.opacity(0.1), in: Capsule())
    }

    private func stepButton(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.85)).frame(width: 22, height: 22)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func circleButton(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 30, height: 30)
                .background(.white.opacity(0.1), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }

    private var progressRow: some View {
        HStack(spacing: 10) {
            Text(NotchTeleprompterSupport.clock(service.elapsed))
                .font(.system(size: 11)).monospacedDigit().foregroundStyle(.white.opacity(0.7))
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.14)).frame(height: 4)
                    Capsule().fill(Color.yellow).frame(width: max(4, proxy.size.width * service.progress), height: 4)
                    Circle().fill(Color.white).frame(width: 10, height: 10)
                        .offset(x: max(0, proxy.size.width * service.progress - 5))
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    service.seek(to: value.location.x / max(1, proxy.size.width))
                })
            }
            .frame(height: 16)
            Text("-" + NotchTeleprompterSupport.clock(max(0, service.total - service.elapsed)))
                .font(.system(size: 11)).monospacedDigit().foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 4)
    }

    // MARK: Empty

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "text.alignleft").font(.system(size: 26, weight: .light))
                .foregroundStyle(.white.opacity(0.45)).accessibilityHidden(true)
            Text(text.empty).font(.system(size: 13, weight: .semibold))
            Text(text.emptyHint).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
            HStack(spacing: 8) {
                NotchPillButton(title: text.writeScript) { beginEditing() }
                NotchPillButton(title: text.pasteScript, prominent: true) {
                    if let pasted = NotchTeleprompterService.clipboardText() {
                        service.setScript(pasted)
                    } else {
                        beginEditing()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Editing

    private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                NotchIconButton(symbol: "chevron.left", title: text.back) { finishEditing() }
                Text(text.editorTitle).font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 6)
                Text(String(format: text.wordsFormat, NotchTeleprompterSupport.wordCount(draft)))
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)).monospacedDigit()
            }
            ZStack(alignment: .topLeading) {
                PlainTextEditor(text: $draft, fontSize: 13, textColor: .white,
                                textContainerInset: NSSize(width: 6, height: 8)) { view in
                    view.insertionPointColor = .white
                    editorView = view
                    DispatchQueue.main.async { focusEditor() }
                }
                if draft.isEmpty {
                    Text(text.placeholder).font(.system(size: 13)).foregroundStyle(.white.opacity(0.4))
                        .padding(.leading, 6 + PlainTextEditor.lineFragmentPadding).padding(.top, 8)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            HStack(spacing: 8) {
                NotchPillButton(title: text.paste) { pasteIntoDraft() }
                NotchPillButton(title: text.clear) { draft = ""; focusEditor() }
                Spacer(minLength: 6)
                NotchPillButton(title: text.done, prominent: true) { finishEditing() }
            }
        }
    }

    private func beginEditing() {
        draft = service.script
        service.pause()
        service.isEditing = true
    }

    private func finishEditing() {
        service.setScript(draft.trimmingCharacters(in: .whitespacesAndNewlines))
        service.isEditing = false
    }

    /// The clipboard's text goes in after what is written, on a new line.
    private func pasteIntoDraft() {
        guard let pasted = NotchTeleprompterService.clipboardText() else { return }
        let current = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = current.isEmpty ? pasted : current + "\n" + pasted
        focusEditor()
    }

    private func focusEditor() {
        guard let view = editorView, let window = view.window, window.isKeyWindow else { return }
        window.makeFirstResponder(view)
        let end = NSRange(location: (view.string as NSString).length, length: 0)
        view.setSelectedRange(end)
        view.scrollRangeToVisible(end)
    }
}
