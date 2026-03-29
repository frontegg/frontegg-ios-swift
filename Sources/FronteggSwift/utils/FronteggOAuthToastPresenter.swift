import UIKit

@MainActor
final class FronteggOAuthToastPresenter {
    static let shared = FronteggOAuthToastPresenter()

    private weak var activeToastView: UIView?
    private var dismissWorkItem: DispatchWorkItem?
    private var presentationRetryWorkItem: DispatchWorkItem?
    private let presentationRetryInterval: TimeInterval = 0.15
    private let maxPresentationRetryAttempts = 60
    private let displayDuration: TimeInterval = 10

    private init() {}

    func show(message: String, in window: UIWindow?) {
        dismissCurrentToast(animated: false)
        cancelPendingPresentation()

        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else {
            return
        }

        presentToast(
            message: trimmedMessage,
            preferredWindow: window,
            remainingAttempts: maxPresentationRetryAttempts
        )
    }

    private func presentToast(
        message: String,
        preferredWindow: UIWindow?,
        remainingAttempts: Int
    ) {
        guard let window = resolvePresentationWindow(preferredWindow) else {
            guard remainingAttempts > 0 else {
                return
            }

            let workItem = DispatchWorkItem { [weak self] in
                self?.presentToast(
                    message: message,
                    preferredWindow: preferredWindow,
                    remainingAttempts: remainingAttempts - 1
                )
            }
            presentationRetryWorkItem = workItem
            DispatchQueue.main.asyncAfter(
                deadline: .now() + presentationRetryInterval,
                execute: workItem
            )
            return
        }

        presentationRetryWorkItem = nil
        showToast(message: message, in: window)
    }

    private func resolvePresentationWindow(_ preferredWindow: UIWindow?) -> UIWindow? {
        if let preferredWindow, isUsablePresentationWindow(preferredWindow) {
            return preferredWindow
        }

        guard let candidate = UIWindow.fronteggPresentationCandidate,
              isUsablePresentationWindow(candidate) else {
            return nil
        }

        return candidate
    }

    private func isUsablePresentationWindow(_ window: UIWindow) -> Bool {
        if let scene = window.windowScene {
            switch scene.activationState {
            case .foregroundActive, .foregroundInactive:
                break
            default:
                return false
            }
        }

        return !window.isHidden && window.alpha > 0 && !window.bounds.isEmpty
    }

    private func showToast(message: String, in window: UIWindow) {
        let presentationView = window
        window.layoutIfNeeded()
        presentationView.layoutIfNeeded()

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = UIColor(white: 0.08, alpha: 0.94)
        container.layer.cornerRadius = 12
        container.layer.masksToBounds = true
        container.alpha = 0
        container.transform = CGAffineTransform(translationX: 0, y: -8)
        container.isAccessibilityElement = true
        container.accessibilityIdentifier = "OAuthErrorToast"
        container.accessibilityLabel = message
        container.accessibilityValue = message
        container.accessibilityTraits = .staticText
        container.isUserInteractionEnabled = false

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = message
        label.textColor = .white
        label.font = UIFont.preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.textAlignment = .center

        container.addSubview(label)
        presentationView.addSubview(container)
        presentationView.bringSubviewToFront(container)

        let maxWidth = max(220, min(presentationView.bounds.width - 32, 420))
        let topAnchor = presentationView.safeAreaLayoutGuide.topAnchor
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            container.centerXAnchor.constraint(equalTo: presentationView.centerXAnchor),
            container.leadingAnchor.constraint(greaterThanOrEqualTo: presentationView.leadingAnchor, constant: 16),
            container.trailingAnchor.constraint(lessThanOrEqualTo: presentationView.trailingAnchor, constant: -16),
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
        DispatchQueue.main.asyncAfter(deadline: .now() + displayDuration, execute: dismissWorkItem)
    }

    private func cancelPendingPresentation() {
        presentationRetryWorkItem?.cancel()
        presentationRetryWorkItem = nil
    }

    private func dismissCurrentToast(animated: Bool) {
        cancelPendingPresentation()
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
