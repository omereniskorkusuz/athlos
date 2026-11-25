import AppKit
import SwiftUI

/// Size of the desktop widget.
enum DesktopWidgetSize: String, CaseIterable, Identifiable {
    case small, medium, large
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large (with calendar)"
        }
    }

    var width: CGFloat {
        switch self {
        case .small: 250
        case .medium: 300
        case .large: 320
        }
    }
}

/// A borderless panel pinned to the desktop: it sits below windows and above desktop icons,
/// it shows on every desktop Space and can be clicked (start/stop the timer).
/// Note: macOS's built-in widgets (WidgetKit) need an extension built with Xcode; this panel
/// gives the same experience without Xcode.
@MainActor
final class DesktopWidgetController {
    private static let enabledKey = "desktopWidget.enabled"
    private static let sizeKey = "desktopWidget.size"
    private static let frameName = "AthlosDesktopWidget"

    private weak var model: AppModel?
    private var panel: NSPanel?

    init(model: AppModel) {
        self.model = model
    }

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.enabledKey) }
    }

    var size: DesktopWidgetSize {
        get { DesktopWidgetSize(rawValue: UserDefaults.standard.string(forKey: Self.sizeKey) ?? "") ?? .medium }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.sizeKey)
            if panel != nil { rebuild() }
        }
    }

    /// At launch: show it if it was left open last time.
    func restore() {
        if isEnabled { show() }
    }

    func setVisible(_ visible: Bool) {
        isEnabled = visible
        if visible { show() } else { hide() }
    }

    private func show() {
        if panel == nil { rebuild() }
        panel?.orderFrontRegardless()
    }

    private func hide() {
        panel?.orderOut(nil)
    }

    /// (Re)builds the panel; called when the size changes. The position is remembered.
    private func rebuild() {
        guard let model else { return }
        let oldOrigin = panel?.frame.origin
        panel?.orderOut(nil)

        let host = NSHostingController(rootView: DesktopWidgetView(size: size).environment(model).environment(\.locale, Fmt.locale))
        host.sizingOptions = [.preferredContentSize] // the panel follows its content size
        host.view.wantsLayer = true

        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: size.width, height: 200),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.contentViewController = host
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.becomesKeyOnlyIfNeeded = true
        // Just above the desktop icons: app windows always stay on top of it (like a widget).
        p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        p.isMovableByWindowBackground = true

        if !p.setFrameUsingName(Self.frameName) {
            if let oldOrigin {
                p.setFrameOrigin(oldOrigin)
            } else if let screen = NSScreen.main {
                // First launch: top right of the screen
                let v = screen.visibleFrame
                p.setFrameOrigin(NSPoint(x: v.maxX - size.width - 24, y: v.maxY - 260))
            }
        }
        p.setFrameAutosaveName(Self.frameName)
        panel = p
        if isEnabled { p.orderFrontRegardless() }
    }
}
