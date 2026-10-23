import AppKit

/// The blurred backdrop behind a translucent panel, masked to the panel's
/// shape by the window. Offscreen renders leave it out: it shows what is
/// behind the window, which a bitmap cannot capture.
enum PanelBackground {
    @MainActor
    static func makeView() -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .clear
            return glass
        } else {
            let effect = NSVisualEffectView()
            effect.blendingMode = .behindWindow
            effect.material = .hudWindow
            effect.state = .active
            return effect
        }
    }
}
