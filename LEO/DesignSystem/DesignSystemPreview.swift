import SwiftUI

struct DesignSystemPreview: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                    colorsSection
                    typographySection
                    buttonsSection
                    chipsSection
                    cardSection
                    emptyStateSection
                    errorBannerSection
                }
                .padding(Theme.Spacing.lg)
            }
            .background(Theme.Color.background)
            .navigationTitle("Design System")
        }
    }

    private var colorsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Colors").font(Theme.Typography.title)
            LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 3), spacing: Theme.Spacing.sm) {
                colorSwatch("Background", Theme.Color.background)
                colorSwatch("Surface", Theme.Color.surface)
                colorSwatch("Elevated", Theme.Color.surfaceElevated)
                colorSwatch("Accent", Theme.Color.accent)
                colorSwatch("Accent Muted", Theme.Color.accentMuted)
                colorSwatch("Text Primary", Theme.Color.textPrimary)
                colorSwatch("Text Secondary", Theme.Color.textSecondary)
                colorSwatch("Success", Theme.Color.success)
                colorSwatch("Warning", Theme.Color.warning)
                colorSwatch("Danger", Theme.Color.danger)
            }
        }
    }

    private func colorSwatch(_ name: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .fill(color)
                .frame(height: 44)
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.sm).strokeBorder(Theme.Color.divider, lineWidth: 0.5))
            Text(name).font(Theme.Typography.caption).foregroundStyle(Theme.Color.textSecondary)
        }
    }

    private var typographySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Typography").font(Theme.Typography.title)
            Group {
                Text("Large Title").font(Theme.Typography.largeTitle)
                Text("Title").font(Theme.Typography.title)
                Text("Headline").font(Theme.Typography.headline)
                Text("Body text, a bit longer to show line wrapping behavior across sizes").font(Theme.Typography.body)
                Text("Callout").font(Theme.Typography.callout)
                Text("Caption text").font(Theme.Typography.caption)
            }
            .foregroundStyle(Theme.Color.textPrimary)
        }
    }

    private var buttonsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Buttons").font(Theme.Typography.title)
            LEOButton("Primary Action") {}
            LEOButton("Secondary", style: .secondary) {}
            LEOButton("Delete Item", style: .destructive) {}
        }
    }

    private var chipsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Chips").font(Theme.Typography.title)
            HStack(spacing: Theme.Spacing.sm) {
                LEOChip(label: "Work", icon: "briefcase.fill")
                LEOChip(label: "Health", icon: "heart.fill", color: Theme.Color.success)
                LEOChip(label: "Urgent", color: Theme.Color.danger)
                LEOChip(label: "Personal")
            }
        }
    }

    private var cardSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Card").font(Theme.Typography.title)
            LEOCard {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Draft Q3 Report").font(Theme.Typography.headline)
                    Text("Due Friday").font(Theme.Typography.callout).foregroundStyle(Theme.Color.textSecondary)
                }
            }
        }
    }

    private var emptyStateSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Empty State").font(Theme.Typography.title)
            LEOEmptyState(
                title: "Nothing today",
                message: "Capture anything you owe your future self.",
                icon: "calendar.badge.plus",
                action: ("Add something", {})
            )
        }
    }

    private var errorBannerSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Error Banner").font(Theme.Typography.title)
            ErrorBanner(message: "Could not sync with iCloud.", retry: {})
            ErrorBanner(message: "Notification permission denied.")
        }
    }
}

#Preview("Light") { DesignSystemPreview() }
#Preview("Dark") { DesignSystemPreview().preferredColorScheme(.dark) }
