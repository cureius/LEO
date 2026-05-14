import SwiftUI

// MARK: - macOS no-op shims for iOS-only View modifiers
// These let shared view code compile on macOS without platform conditionals scattered everywhere.

#if os(macOS)

// NavigationBarItem doesn't exist on macOS; shadow it so call sites compile unchanged
enum NavigationBarItem {
    enum TitleDisplayMode { case automatic, inline, large }
}

extension View {
    // Navigation bar style — macOS uses NavigationStack without a bar
    func navigationBarTitleDisplayMode(_ mode: NavigationBarItem.TitleDisplayMode) -> some View { self }

    // Keyboard autocapitalization — no concept on macOS hardware keyboards
    func textInputAutocapitalization(_ type: TextInputAutocapitalization?) -> some View { self }

    // presentationDetents IS available on macOS 13+ — no shim needed
    // presentationCornerRadius is iOS-only
    func presentationCornerRadius(_ cornerRadius: CGFloat?) -> some View { self }

    // Keyboard types — macOS has hardware keyboards, no soft keyboard type
    func keyboardType(_ type: UIKeyboardType) -> some View { self }
}

// UIKeyboardType stub on macOS
enum UIKeyboardType {
    case `default`, asciiCapable, numbersAndPunctuation, URL, numberPad
    case phonePad, namePhonePad, emailAddress, decimalPad, twitter, webSearch, asciiCapableNumberPad
}

// TextInputAutocapitalization doesn't exist on macOS — provide a stub type
struct TextInputAutocapitalization: Equatable {
    static let never      = TextInputAutocapitalization()
    static let words      = TextInputAutocapitalization()
    static let sentences  = TextInputAutocapitalization()
    static let characters = TextInputAutocapitalization()
}
// scrollDismissesKeyboard and ScrollDismissesKeyboardMode are available on macOS 13+ — no shim needed

#endif

// MARK: - Cross-platform ToolbarItemPlacement helpers
// topBarLeading / topBarTrailing are iOS-only; map to equivalent Mac placements

extension ToolbarItemPlacement {
    #if os(macOS)
    static var leoTopBarLeading: ToolbarItemPlacement  { .navigation }
    static var leoTopBarTrailing: ToolbarItemPlacement { .primaryAction }
    #else
    static var leoTopBarLeading: ToolbarItemPlacement  { .topBarLeading }
    static var leoTopBarTrailing: ToolbarItemPlacement { .topBarTrailing }
    #endif
}

// MARK: - Color cross-platform helpers

extension Color {
    /// iOS `Color(.systemBackground)` maps to macOS window background
    static var leoBackground: Color {
        #if os(iOS)
        Color(.systemBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }

    /// iOS `Color(.secondarySystemBackground)` maps to macOS control background
    static var leoSecondaryBackground: Color {
        #if os(iOS)
        Color(.secondarySystemBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }

    /// iOS `Color(.tertiaryLabel)` maps to macOS tertiary label
    static var leoTertiaryLabel: Color {
        #if os(iOS)
        Color(.tertiaryLabel)
        #else
        Color(nsColor: .tertiaryLabelColor)
        #endif
    }
}

// MARK: - NavigationBarItem.TitleDisplayMode on macOS
// The type exists in SwiftUI on both platforms; only the view modifier is missing (stubbed above)
