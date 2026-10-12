// ColonSuggestionPanel.swift
// Slack-style autocomplete popup for colon shortcuts. Appears anchored at
// the caret of the frontmost app while the user types `:name…`, lists up
// to 8 ranked suggestions, and inserts the highlighted pick on Enter/Tab
// or a mouse click.
//
// Design constraints:
// - NON-ACTIVATING: the target app must never lose focus. The panel cannot
//   become key/main; keyboard navigation arrives through the CGEvent tap in
//   EmojiShortcutMonitor, which swallows ↑/↓/Enter/Tab/Esc only while this
//   panel is visible. Plain characters always pass through to the app.
// - One AX round-trip per popup session: caret bounds are queried when the
//   panel first appears; live updates as the user keeps typing only resize
//   (anchoring the top-left corner) — no per-keystroke AX calls.
// - Falls back to the mouse location when the caret bounds are unavailable.

import Cocoa
import SwiftUI

// MARK: - View model

final class ColonSuggestionViewModel: ObservableObject {
    @Published private(set) var items: [EmojiSuggestion] = []
    @Published private(set) var selectedID: String?

    /// Fired when the user clicks a row. Keyboard selection is handled by
    /// the monitor (it owns the event tap), not here.
    var pick: ((EmojiSuggestion) -> Void)?

    var selected: EmojiSuggestion? {
        items.first { $0.id == selectedID } ?? items.first
    }

    /// Replace the suggestion list, keeping the current selection if it is
    /// still present, otherwise resetting to the top row.
    func update(_ newItems: [EmojiSuggestion]) {
        items = newItems
        if let selectedID, newItems.contains(where: { $0.id == selectedID }) {
            self.selectedID = selectedID
        } else {
            selectedID = newItems.first?.id
        }
    }

    func moveSelection(_ delta: Int) {
        guard !items.isEmpty else { return }
        let current = items.firstIndex { $0.id == selectedID } ?? 0
        let next = min(max(current + delta, 0), items.count - 1)
        selectedID = items[next].id
    }

    func select(_ id: String) {
        guard items.contains(where: { $0.id == id }) else { return }
        selectedID = id
    }

    func reset() {
        items = []
        selectedID = nil
    }
}

// MARK: - Panel

final class ColonSuggestionPanel: NSPanel {
    static let shared = ColonSuggestionPanel()

    private let viewModel = ColonSuggestionViewModel()
    private var hosting: NSHostingView<ColonSuggestionView>?

    /// Caret edges in AppKit global coordinates, captured when the popup
    /// appears; the panel stays anchored between keystrokes.
    private var caretTopY: CGFloat?
    private var caretBottomY: CGFloat?
    private var anchorX: CGFloat?

    /// Fired when a row is clicked.
    var onPick: ((EmojiSuggestion) -> Void)?

    var selected: EmojiSuggestion? { viewModel.selected }

    fileprivate static let rowHeight: CGFloat = 30
    fileprivate static let panelWidth: CGFloat = 280
    private static let maxRows = 8

    private convenience init() {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: ColonSuggestionPanel.panelWidth, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
    }

    private override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask,
                          backing bufferType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: bufferType, defer: flag)
        isFloatingPanel = true
        level = .popUpMenu
        hidesOnDeactivate = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isMovable = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        let view = ColonSuggestionView(viewModel: viewModel)
        let hosting = NSHostingView(rootView: view)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        contentView?.addSubview(hosting)
        hosting.leadingAnchor.constraint(equalTo: contentView!.leadingAnchor).isActive = true
        hosting.trailingAnchor.constraint(equalTo: contentView!.trailingAnchor).isActive = true
        hosting.topAnchor.constraint(equalTo: contentView!.topAnchor).isActive = true
        hosting.bottomAnchor.constraint(equalTo: contentView!.bottomAnchor).isActive = true
        self.hosting = hosting

        viewModel.pick = { [weak self] suggestion in
            self?.onPick?(suggestion)
        }
    }

    // The panel must never steal key/main status from the target app.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // MARK: - Public API

    /// Populate and position the panel at the caret of `pid`. Call on the
    /// main thread (the event tap runs on the main run loop).
    func showSuggestions(_ items: [EmojiSuggestion], nearCaretOf pid: pid_t) {
        if items.isEmpty {
            hide()
            return
        }
        viewModel.update(items)

        if caretTopY == nil || !isVisible {
            captureCaretAnchor(for: pid)
        }
        resizeKeepingTopAnchor()
        if let origin = computedOrigin() {
            setFrameOrigin(origin)
        }
        alphaValue = 1
        orderFrontRegardless()
    }

    /// Live update while buffering more characters. Keeps the anchor fixed
    /// (caret drifts only a few chars) and resizes the visible rows.
    func updateSuggestions(_ items: [EmojiSuggestion]) {
        if items.isEmpty {
            hide()
            return
        }
        guard isVisible else { return }
        viewModel.update(items)
        resizeKeepingTopAnchor()
        if let origin = computedOrigin() {
            setFrameOrigin(origin)   // keep top edge anchored as rows change
        }
    }

    func moveSelection(_ delta: Int) {
        viewModel.moveSelection(delta)
    }

    func hide() {
        guard isVisible else { return }
        orderOut(nil)
        caretTopY = nil
        caretBottomY = nil
        anchorX = nil
    }

    // MARK: - Layout & positioning

    private func resizeKeepingTopAnchor() {
        let rows = min(viewModel.items.count, Self.maxRows)
        let newHeight = CGFloat(rows) * Self.rowHeight + 12
        setContentSize(NSSize(width: Self.panelWidth, height: newHeight))
    }

    /// Capture the caret's AppKit-global top/bottom edges and anchor x.
    /// One AX round-trip per popup session.
    private func captureCaretAnchor(for pid: pid_t) {
        let gap: CGFloat = 4
        if let axRect = AXTextInserter.caretBounds(at: pid) {
            // AX global coords: origin top-left of the primary display,
            // y grows downward. AppKit: origin bottom-left, y grows upward.
            let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
            caretBottomY = primaryTop - (axRect.origin.y + axRect.height)
            caretTopY = primaryTop - axRect.origin.y
            anchorX = axRect.origin.x
        } else {
            // Fallback: dock under the mouse cursor.
            let mouse = NSEvent.mouseLocation
            caretBottomY = mouse.y - gap
            caretTopY = mouse.y
            anchorX = mouse.x - 10
        }
    }

    /// Panel origin (bottom-left): below the caret, flipping above when it
    /// would hang off the bottom, clamped inside the caret's screen.
    private func computedOrigin() -> CGPoint? {
        guard let caretBottomY, let caretTopY, let anchorX else { return nil }
        let gap: CGFloat = 4
        let screen = self.screen(containing: CGPoint(x: anchorX, y: caretBottomY))
        let visible = screen.visibleFrame

        var origin = CGPoint(x: anchorX, y: caretBottomY - gap - frame.height)
        if origin.y < visible.minY + 4 {
            origin.y = min(caretTopY + gap, visible.maxY - frame.height - 4)
        }
        origin.x = min(max(origin.x, visible.minX + 4), visible.maxX - frame.width - 4)
        return origin
    }

    private func screen(containing point: CGPoint) -> NSScreen {
        NSScreen.screens.first { $0.frame.insetBy(dx: -40, dy: -40).contains(point) }
            ?? NSScreen.main
            ?? NSScreen.screens.first!
    }
}

// MARK: - SwiftUI content

private struct ColonSuggestionView: View {
    @ObservedObject var viewModel: ColonSuggestionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(viewModel.items) { suggestion in
                Button {
                    viewModel.pick?(suggestion)
                } label: {
                    HStack(spacing: 8) {
                        Text(suggestion.emoji.emoji)
                            .font(.system(size: 18))
                            .frame(width: 24, alignment: .center)
                        Text(":\(suggestion.shortname):")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)
                        Spacer(minLength: 4)
                        Text(suggestion.emoji.name)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: ColonSuggestionPanel.rowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(viewModel.selectedID == suggestion.id
                              ? Color.accentColor.opacity(0.25)
                              : Color.clear)
                )
                .onHover { hovering in
                    if hovering { viewModel.select(suggestion.id) }
                }
            }
        }
        .padding(6)
        .frame(width: ColonSuggestionPanel.panelWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }
}
