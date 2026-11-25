import SwiftUI
import AthlosCore

/// Shows a project icon (emoji / SF Symbol / uploaded logo) in a rounded square.
struct ProjectIconView: View {
    let icon: ProjectIcon
    let color: Color
    var size: CGFloat = 28
    var images: ImageStore?

    init(project: Project, size: CGFloat = 28, images: ImageStore?) {
        self.icon = project.icon
        self.color = project.color
        self.size = size
        self.images = images
    }

    init(icon: ProjectIcon, color: Color, size: CGFloat = 28, images: ImageStore?) {
        self.icon = icon
        self.color = color
        self.size = size
        self.images = images
    }

    private var corner: CGFloat { size * 0.24 }

    var body: some View {
        Group {
            switch icon {
            case .emoji(let e):
                Text(e)
                    .font(.system(size: size * 0.62))
                    .frame(width: size, height: size)
                    .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: corner, style: .continuous))
            case .symbol(let name):
                Image(systemName: name)
                    .font(.system(size: size * 0.48, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(color.gradient, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
            case .image(let name):
                if let images, let ns = NSImage(contentsOf: images.url(for: name)) {
                    Image(nsImage: ns)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size, height: size)
                        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: size * 0.45))
                        .foregroundStyle(.secondary)
                        .frame(width: size, height: size)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Empty state (Apple's ContentUnavailableView + an action).
struct EmptyStateView: View {
    let title: LocalizedStringKey
    let systemImage: String
    let message: LocalizedStringKey
    var actionTitle: LocalizedStringKey?
    var action: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
    }
}

/// Small statistic tile.
struct StatTile: View {
    let title: LocalizedStringKey
    let value: String
    var systemImage: String
    var tint: Color = Theme.gold

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.inkSecondary)
            Text(value)
                .font(Theme.display(24))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .athlosCard(radius: 14)
        .overlay(alignment: .topTrailing) {
            Circle().fill(tint).frame(width: 8, height: 8).padding(12)
        }
        .accessibilityElement(children: .combine)
    }
}
