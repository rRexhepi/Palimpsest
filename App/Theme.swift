import SwiftUI

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

enum Theme {
    static let canvas         = adaptive(light: (244, 239, 230), dark: ( 27,  24,  21))
    static let canvasCool     = adaptive(light: (237, 232, 221), dark: ( 21,  18,  15))
    static let canvasDeep     = adaptive(light: (226, 219, 203), dark: ( 14,  12,  10))

    static let ink            = adaptive(light: ( 31,  26,  20), dark: (233, 226, 212))
    static let inkSoft        = adaptive(light: ( 61,  53,  42), dark: (198, 190, 174))
    static let inkMuted       = adaptive(light: (107,  98,  83), dark: (140, 133, 121))

    static let hairline       = adaptive(light: (217, 208, 189), dark: ( 58,  51,  43))
    static let hairlineStrong = adaptive(light: (191, 179, 154), dark: ( 75,  68,  58))

    static let accent         = adaptive(light: (139,  90,  43), dark: (201, 154, 106))
    static let accentDeep     = adaptive(light: (110,  69,  32), dark: (164, 124,  80))
    static let onAccent       = adaptive(light: (251, 247, 238), dark: ( 27,  24,  21))

    static let highlightSentence = adaptive(light: (199, 151,  63), dark: (217, 177, 134))
    static let highlightWordSoft = adaptive(light: (250, 239, 203), dark: ( 90,  75,  50))
}

private func adaptive(light: (Int, Int, Int), dark: (Int, Int, Int)) -> Color {
    // Prefer UIKit when available — that covers iOS, iPadOS, AND Mac
    // Catalyst. Catalyst exposes `canImport(AppKit)` as true but most
    // AppKit color types (NSColor in particular) aren't available there,
    // so the AppKit branch can only run on a pure-AppKit macOS target.
    #if canImport(UIKit)
    let lightUI = UIColor(red: CGFloat(light.0)/255, green: CGFloat(light.1)/255, blue: CGFloat(light.2)/255, alpha: 1)
    let darkUI  = UIColor(red: CGFloat(dark.0)/255,  green: CGFloat(dark.1)/255,  blue: CGFloat(dark.2)/255,  alpha: 1)
    return Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? darkUI : lightUI
    })
    #elseif canImport(AppKit)
    let lightNS = NSColor(srgbRed: CGFloat(light.0)/255, green: CGFloat(light.1)/255, blue: CGFloat(light.2)/255, alpha: 1)
    let darkNS  = NSColor(srgbRed: CGFloat(dark.0)/255,  green: CGFloat(dark.1)/255,  blue: CGFloat(dark.2)/255,  alpha: 1)
    return Color(nsColor: NSColor(name: nil) { appearance in
        let darkAppearances: [NSAppearance.Name] = [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua, .accessibilityHighContrastVibrantDark]
        return appearance.bestMatch(from: darkAppearances) != nil ? darkNS : lightNS
    })
    #else
    return Color(red: CGFloat(light.0)/255, green: CGFloat(light.1)/255, blue: CGFloat(light.2)/255)
    #endif
}
