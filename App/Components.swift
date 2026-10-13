import SwiftUI
import FamilyControls
import ManagedSettings

// Apple's token labels are rendered remotely; reserve room while they load.
struct SelectionRows: View {
    let selection: FamilyActivitySelection

    var body: some View {
        Group {
            ForEach(Array(selection.applicationTokens), id: \.self) { token in Label(token) }
            ForEach(Array(selection.categoryTokens), id: \.self) { token in Label(token) }
            ForEach(Array(selection.webDomainTokens), id: \.self) { token in Label(token) }
        }
        .labelStyle(.titleAndIcon)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 44)
    }
}

extension FamilyActivitySelection {
    var summary: String {
        let counts = [(applicationTokens.count, "app", "apps"),
                      (categoryTokens.count, "category", "categories"),
                      (webDomainTokens.count, "website", "websites")]
        let parts = counts.compactMap { count, singular, plural -> String? in
            count == 0 ? nil : "\(count) \(count == 1 ? singular : plural)"
        }
        return parts.isEmpty ? "Nothing selected" : parts.joined(separator: " · ")
    }
}

enum Brand {
    static let oceanNight = Color(red: 11 / 255, green: 8 / 255, blue: 23 / 255)
    static let ink = Color.primary
    static let background = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
}

/// Full scene with no side margins; only its top and bottom dissolve into the page.
struct OceanSunsetBackdrop: View {
    var animated = true

    var body: some View {
        Group {
            if animated {
                OceanSunsetArtwork()
                    .mask {
                        LinearGradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .white, location: 0.16),
                            .init(color: .white, location: 0.74),
                            .init(color: .clear, location: 1)
                        ], startPoint: .top, endPoint: .bottom)
                    }
            } else {
                // The launch stills already contain the same top/bottom fade.
                Image("LaunchArtwork").resizable().scaledToFit()
            }
        }
        .aspectRatio(2, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}

struct DaywellLoadingView: View {
    var body: some View {
        ZStack {
            Color("LaunchBackground").ignoresSafeArea()
            VStack(spacing: 0) {
                OceanSunsetBackdrop(animated: false)
                VStack(spacing: 24) {
                    Text("Daywell").font(.system(size: 28, weight: .semibold))
                    ProgressView().tint(Color(uiColor: .label)).accessibilityLabel("Loading your routine")
                }
                .padding(.top, -24)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
        }
        .ignoresSafeArea(.container, edges: .horizontal)
    }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(padding).frame(maxWidth: .infinity, alignment: .leading)
            .background(Brand.card, in: RoundedRectangle(cornerRadius: 24))
    }
}

struct PrimaryButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded, weight: .semibold))
            .frame(maxWidth: .infinity).padding(.vertical, 17)
            .foregroundStyle(.white)
            .background(Color(uiColor: .systemBlue).opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.4),
                        in: RoundedRectangle(cornerRadius: 18))
            .opacity(enabled ? 1 : 0.6)
    }
}

struct SectionHeading: View {
    let title: String
    var body: some View {
        Text(title.uppercased()).font(.system(.caption, design: .rounded, weight: .bold))
            .tracking(1.5).foregroundStyle(.secondary)
    }
}

struct ErrorMessage: View {
    let message: String
    var body: some View {
        Label(message, systemImage: "exclamationmark.circle.fill")
            .font(.subheadline).foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16).background(Color.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
            .accessibilityIdentifier("protection-error")
    }
}

func timeLabel(_ minute: Int) -> String {
    // Fixed 24-hour labels make midnight and the requested AM/PM windows unambiguous.
    String(format: "%02d:%02d", minute / 60, minute % 60)
}
