import SwiftUI

// Catalyst exposes both UIKit and AppKit but `NSImage(data:)` is
// unavailable there — `canImport(AppKit)` alone would route us into the
// AppKit branch and break the build. Prefer UIKit when present, which
// covers iOS, iPadOS, and Mac Catalyst.
#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
#endif

extension Image {
    init?(platformData data: Data) {
        guard let image = PlatformImage(data: data) else { return nil }
        #if canImport(UIKit)
        self.init(uiImage: image)
        #elseif canImport(AppKit)
        self.init(nsImage: image)
        #endif
    }
}
