import SwiftUI

/// Central design token namespace. All views consume tokens from here; no hardcoded values anywhere else.
enum Theme {
    enum Color {
        static let background       = SwiftUI.Color("Theme/Background")
        static let surface          = SwiftUI.Color("Theme/Surface")
        static let surfaceElevated  = SwiftUI.Color("Theme/SurfaceElevated")
        static let accent           = SwiftUI.Color("Theme/Accent")
        static let accentMuted      = SwiftUI.Color("Theme/AccentMuted")
        static let textPrimary      = SwiftUI.Color("Theme/TextPrimary")
        static let textSecondary    = SwiftUI.Color("Theme/TextSecondary")
        static let divider          = SwiftUI.Color("Theme/Divider")
        static let success          = SwiftUI.Color("Theme/Success")
        static let warning          = SwiftUI.Color("Theme/Warning")
        static let danger           = SwiftUI.Color("Theme/Danger")
    }

    enum Spacing {
        static let xs:  CGFloat = 4
        static let sm:  CGFloat = 8
        static let md:  CGFloat = 12
        static let lg:  CGFloat = 16
        static let xl:  CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let sm: CGFloat = 6
        static let md: CGFloat = 10
        static let lg: CGFloat = 16
    }

    enum Typography {
        static let largeTitle = SwiftUI.Font.largeTitle.weight(.bold)
        static let title      = SwiftUI.Font.title2.weight(.semibold)
        static let headline   = SwiftUI.Font.headline
        static let body       = SwiftUI.Font.body
        static let callout    = SwiftUI.Font.callout
        static let caption    = SwiftUI.Font.caption
    }
}
