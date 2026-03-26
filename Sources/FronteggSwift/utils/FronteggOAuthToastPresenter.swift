import UIKit

@MainActor
final class FronteggOAuthToastPresenter {
    static let shared = FronteggOAuthToastPresenter()

    private weak var activeToastView: UIView?
    private var dismissWorkItem: DispatchWorkItem?

    private init() {}

    func show(message: String, in window: UIWindow?) {
        dismissCurrentToast(animated: false)

        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else {
            return
        }
        guard let window = window ?? UIWindow.fronteggPresentationCandidate else {
            return
        }

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = UIColor(white: 0.08, alpha: 0.94)
        container.layer.cornerRadius = 12
        container.layer.masksToBounds = true
        container.alpha = 0
        container.transform = CGAffineTransform(translationX: 0, y: -8)
        container.isAccessibilityElement = true
        container.accessibilityIdentifier = "OAuthErrorToast"
        container.accessibilityLabel = trimmedMessage
        container.accessibilityValue = trimmedMessage
        container.accessibilityTraits = .staticText

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = trimmedMessage
        label.textColor = .white
        label.font = UIFont.preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.textAlignment = .center

        container.addSubview(label)
        window.addSubview(container)
        window.bringSubviewToFront(container)

        let maxWidth = max(220, min(window.bounds.width - 32, 420))
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: window.safeAreaLayoutGuide.topAnchor, constant: 12),
            container.centerXAnchor.constraint(equalTo: window.centerXAnchor),
            container.leadingAnchor.constraint(greaterThanOrEqualTo: window.leadingAnchor, constant: 16),
            container.trailingAnchor.constraint(lessThanOrEqualTo: window.trailingAnchor, constant: -16),
            container.widthAnchor.constraint(lessThanOrEqualToConstant: maxWidth),

            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12)
        ])

        activeToastView = container

        UIView.animate(withDuration: 0.2) {
            container.alpha = 1
            container.transform = .identity
        }

        let dismissWorkItem = DispatchWorkItem { [weak self, weak container] in
            guard let self, let container else { return }
            UIView.animate(
                withDuration: 0.2,
                animations: {
                    container.alpha = 0
                    container.transform = CGAffineTransform(translationX: 0, y: -8)
                },
                completion: { _ in
                    container.removeFromSuperview()
                    if self.activeToastView === container {
                        self.activeToastView = nil
                    }
                }
            )
        }

        self.dismissWorkItem = dismissWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: dismissWorkItem)
    }

    private func dismissCurrentToast(animated: Bool) {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil

        guard let activeToastView else { return }
        self.activeToastView = nil

        if animated {
            UIView.animate(
                withDuration: 0.2,
                animations: {
                    activeToastView.alpha = 0
                    activeToastView.transform = CGAffineTransform(translationX: 0, y: -8)
                },
                completion: { _ in
                    activeToastView.removeFromSuperview()
                }
            )
            return
        }

        activeToastView.removeFromSuperview()
    }
}
