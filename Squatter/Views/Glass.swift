import SwiftUI

// Liquid Glass, applied only where the OS has it.
//
// Squatter deploys back to macOS 15, which has no glass at all, so every glass surface needs a
// material fallback that reads the same way. These wrappers keep each pair in one place instead
// of scattering `if #available` through the views.

enum LiquidGlass {
    /// True when the app is running on an OS that draws Liquid Glass.
    ///
    /// Reach for this only for layout that has to follow the material — padding, a divider, a
    /// background the system now supplies itself. For surfaces, use the modifiers below.
    static var isAvailable: Bool {
        if #available(macOS 26.0, *) { true } else { false }
    }

    /// The square chip behind a small icon button. Glass wants a rounder corner than the flat
    /// material chip did.
    static var chipShape: AnyShape {
        AnyShape(RoundedRectangle(cornerRadius: isAvailable ? 8 : 6, style: .continuous))
    }
}

extension View {
    /// Glass behind the view on macOS 26+, `fallback` painted into the same shape below that.
    @ViewBuilder
    func glassSurface(
        in shape: some Shape,
        interactive: Bool = false,
        fallback: some ShapeStyle
    ) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular.interactive(interactive), in: shape)
        } else {
            background(fallback, in: shape)
        }
    }

    /// An ordinary button: glass on macOS 26+, bordered below it.
    @ViewBuilder
    func glassButtonStyle() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }

    /// A button that is part of the window's furniture rather than its content — glass on
    /// macOS 26+, and borderless below it, where a row of bordered chips would be too loud.
    @ViewBuilder
    func chromeButtonStyle() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.plain)
        }
    }

    /// Fades scrolled content into the glass bars above and below it. A no-op below macOS 26,
    /// where the bars are opaque and nothing passes behind them.
    @ViewBuilder
    func softScrollEdges() -> some View {
        if #available(macOS 26.0, *) {
            scrollEdgeEffectStyle(.soft, for: .vertical)
        } else {
            self
        }
    }

    /// A filled, tinted button — glass on macOS 26+, `.borderedProminent` below it.
    @ViewBuilder
    func prominentButtonStyle(tint: Color) -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glassProminent).tint(tint)
        } else {
            buttonStyle(.borderedProminent).tint(tint)
        }
    }
}

/// `GlassEffectContainer` on macOS 26+, a plain passthrough below it. Neighbouring glass surfaces
/// only blend and morph into each other when they share a container.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat?
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}
