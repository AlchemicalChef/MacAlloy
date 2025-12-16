import SwiftUI

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

// MARK: - Platform Colors

/// Cross-platform color definitions for the Alloy UI
public enum PlatformColors {
    /// Primary background color for windows/views
    public static var windowBackground: Color {
        #if os(macOS)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return Color(uiColor: .systemBackground)
        #endif
    }

    /// Secondary background color for controls/panels
    public static var controlBackground: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemBackground)
        #endif
    }

    /// Text background color
    public static var textBackground: Color {
        #if os(macOS)
        return Color(nsColor: .textBackgroundColor)
        #else
        return Color(uiColor: .systemBackground)
        #endif
    }

    /// Label/text color
    public static var label: Color {
        #if os(macOS)
        return Color(nsColor: .labelColor)
        #else
        return Color(uiColor: .label)
        #endif
    }

    /// Secondary label color
    public static var secondaryLabel: Color {
        #if os(macOS)
        return Color(nsColor: .secondaryLabelColor)
        #else
        return Color(uiColor: .secondaryLabel)
        #endif
    }
}

// MARK: - Native Color Type Alias

#if os(macOS)
public typealias NativeColor = NSColor
public typealias NativeFont = NSFont
#else
public typealias NativeColor = UIColor
public typealias NativeFont = UIFont
#endif

// MARK: - Native Color Extensions

extension NativeColor {
    /// Window background color cross-platform
    public static var platformWindowBackground: NativeColor {
        #if os(macOS)
        return .windowBackgroundColor
        #else
        return .systemBackground
        #endif
    }

    /// Control background color cross-platform
    public static var platformControlBackground: NativeColor {
        #if os(macOS)
        return .controlBackgroundColor
        #else
        return .secondarySystemBackground
        #endif
    }

    /// Text background color cross-platform
    public static var platformTextBackground: NativeColor {
        #if os(macOS)
        return .textBackgroundColor
        #else
        return .systemBackground
        #endif
    }

    /// Extract RGB components cross-platform
    public var rgbComponents: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        #if os(macOS)
        let converted = usingColorSpace(.sRGB) ?? self
        return (converted.redComponent, converted.greenComponent, converted.blueComponent, converted.alphaComponent)
        #else
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (red, green, blue, alpha)
        #endif
    }
}

// MARK: - Native Font Extensions

extension NativeFont {
    /// Cross-platform monospaced system font
    public static func platformMonospacedSystemFont(ofSize size: CGFloat, weight: Weight) -> NativeFont {
        #if os(macOS)
        return .monospacedSystemFont(ofSize: size, weight: weight)
        #else
        return .monospacedSystemFont(ofSize: size, weight: weight)
        #endif
    }
}
