import AppKit
import HixupCore

/// Kleines Eingabefeld nach dem Hotkey ("Was hakt?"). Nimmt Tastatureingaben an, ohne die aktive App zu
/// wechseln; Enter speichert, Esc oder Inaktivitaet schliessen es.
@MainActor
final class MarkerNotePanel: NSObject, NSTextFieldDelegate {
    private final class KeyPanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    private static let idleTimeout: Duration = .seconds(8)

    private var panel: NSPanel?
    private var onSubmit: ((String) -> Void)?
    private var dismissTask: Task<Void, Never>?

    func show(onSubmit: @escaping (String) -> Void) {
        close()
        self.onSubmit = onSubmit

        let field = NSTextField()
        field.placeholderString = L10n.tr("Was hakt? Enter speichert, Esc schließt")
        field.font = .systemFont(ofSize: 15)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = self

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.addSubview(field)
        field.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 16),
            field.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -16),
            field.centerYAnchor.constraint(equalTo: effect.centerYAnchor)
        ])

        let panel = KeyPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 48),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.contentView = effect
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        position(panel)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)

        self.panel = panel
        restartTimer()
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.maxY - panel.frame.height - 80))
    }

    private func close() {
        dismissTask?.cancel()
        panel?.orderOut(nil)
        panel = nil
        onSubmit = nil
    }

    private func restartTimer() {
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: Self.idleTimeout)
            guard !Task.isCancelled else { return }
            self?.close()
        }
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidChange(_ notification: Notification) {
        restartTimer()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            let text = textView.string
            let submit = onSubmit
            close()
            submit?(text)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            close()
            return true
        default:
            return false
        }
    }
}
