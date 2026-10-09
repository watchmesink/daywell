import SwiftUI
import FamilyControls
import ManagedSettings

// Apple's token label is rendered remotely; reserve row height so it is not
// collapsed while its private title and icon are loading.
struct SelectedApplicationRow: View {
    let token: ApplicationToken

    var body: some View {
        Label(token)
            .labelStyle(.titleAndIcon)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 44)
    }
}

enum Brand {
    static let lime = Color(red: 0.79, green: 0.92, blue: 0.55)
    static let oceanNight = Color(red: 11 / 255, green: 8 / 255, blue: 23 / 255)
    static let ink = Color.primary
    static let background = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
}

struct OceanSunsetBackground: View {
    var body: some View {
        GeometryReader { geometry in
            Image("OceanSunset")
                .resizable()
                .scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                .overlay {
                    LinearGradient(stops: [
                        .init(color: .black.opacity(0.66), location: 0),
                        .init(color: .black.opacity(0.52), location: 0.5),
                        .init(color: .black.opacity(0.86), location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                }
        }
        .accessibilityHidden(true)
    }
}

struct DaywellLoadingView: View {
    var body: some View {
        ZStack {
            Brand.oceanNight.ignoresSafeArea()
            VStack(spacing: 24) {
                Image("OceanSunset")
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .accessibilityHidden(true)
                Text("Daywell").font(.system(size: 28, weight: .semibold))
                ProgressView().tint(.white).accessibilityLabel("Loading your routine")
            }
            .foregroundStyle(.white)
            .frame(maxWidth: 640)
            .padding(.horizontal, 16)
        }
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
            .foregroundStyle(.black)
            .background(Brand.lime.opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.4),
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
