import AppKit
import ScribeConfig
import ScribeCore

/// A window-free preview using the candidate panel's actual text/layout and
/// drawing code. The caller supplies sample content and displays the image.
@MainActor
public enum CandidatePreview {
    public static func render(_ snapshot: CandidateSnapshot, theme: Theme, isDark: Bool, scale: CGFloat = 2) -> NSImage? {
        guard scale.isFinite, scale > 0 else { return nil }
        let appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)!
        let drawing = PanelTheme(theme, palette: SystemPalette(resolvingIn: appearance))
        guard let image = PanelRenderer.render(PanelContent(snapshot), theme: drawing, appearance: appearance, scale: scale) else {
            return nil
        }
        return NSImage(cgImage: image, size: CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale))
    }
}
