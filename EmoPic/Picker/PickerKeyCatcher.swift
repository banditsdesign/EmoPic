import SwiftUI
import AppKit

/// Invisible view that captures key-downs for the picker window *before* the
/// search field's editor sees them.
///
/// A local monitor runs ahead of normal event dispatch, which is the only way
/// ↑/↓/Tab can drive the results list while the text field holds focus — the
/// field editor eats those keys otherwise (arrows move the caret, Tab walks the
/// focus ring). Returning the event unchanged lets it through; returning nil
/// consumes it.
///
/// Lives in the view rather than the window so keyboard behaviour travels with
/// the picker: the monitor exists exactly as long as the picker's view hierarchy
/// does, and only acts when that window is actually key.
struct PickerKeyCatcher: NSViewRepresentable {
    /// False while a sheet or popover owns the keyboard, so arrow keys still do
    /// what the presented UI expects.
    var isEnabled: Bool
    /// Return true if the event was handled (and should be swallowed).
    var onKey: (NSEvent) -> Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isEnabled = isEnabled
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onKey: onKey) }

    final class Coordinator {
        var onKey: (NSEvent) -> Bool
        var isEnabled: Bool
        fileprivate weak var view: NSView?
        private var monitor: Any?

        init(onKey: @escaping (NSEvent) -> Bool) {
            self.onKey = onKey
            self.isEnabled = true
        }

        func attach(to view: NSView) {
            self.view = view
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.isEnabled, self.view?.window?.isKeyWindow == true else {
                    return event
                }
                return self.onKey(event) ? nil : event
            }
        }

        func detach() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        deinit { detach() }
    }
}
