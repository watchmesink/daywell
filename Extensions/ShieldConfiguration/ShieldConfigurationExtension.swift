import ManagedSettings
import BlockingCore
import ManagedSettingsUI
import UIKit

final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        makeConfiguration(name: application.localizedDisplayName ?? "This app")
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        makeConfiguration(name: application.localizedDisplayName ?? "This app")
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        makeConfiguration(name: webDomain.domain ?? "This website")
    }

    private func makeConfiguration(name: String) -> ShieldConfiguration {
        let now = Date()
        let snapshot = try? ProtectionEnvironment.repository().read().active
        let decision = snapshot?.decision(at: now, calendar: .autoupdatingCurrent)
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        var explanation = "Your block is active."
        if decision?.budgetExhausted == true {
            explanation = ProtectionCopy.allowanceUsed
        } else if decision?.scheduled == true, let end = decision?.nextScheduleTransition {
            explanation = "Your scheduled block ends at \(formatter.string(from: end))."
        }
        return ShieldConfiguration(
            backgroundBlurStyle: .systemMaterial,
            backgroundColor: .systemBackground,
            icon: Self.icon,
            title: .init(text: "\(name) can wait.", color: .label),
            subtitle: .init(text: explanation + "\n\nTime for something else.", color: .secondaryLabel),
            primaryButtonLabel: .init(text: "Close", color: .black),
            primaryButtonBackgroundColor: UIColor(red: 0.77, green: 0.91, blue: 0.48, alpha: 1),
            secondaryButtonLabel: nil)
    }

    /// Render the approved sunset crop at 3x for Apple's fixed image slot.
    private static let icon: UIImage? = makeIcon()

    private static func makeIcon() -> UIImage? {
        let side: CGFloat = 120
        guard let image = UIImage(named: "DaywellIcon") else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = false
        let canvas = CGSize(width: side, height: side)
        return UIGraphicsImageRenderer(size: canvas, format: format).image { _ in
            let bounds = CGRect(origin: .zero, size: canvas)
            UIBezierPath(roundedRect: bounds, cornerRadius: 27).addClip()
            image.draw(in: bounds)
        }.withRenderingMode(.alwaysOriginal)
    }
}
