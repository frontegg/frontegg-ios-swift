//
//  FronteggAuth+OAuthErrors.swift
//
//  Created by David Frontegg on 14/11/2022.
//

import Foundation
import UIKit

extension FronteggAuth {

    func normalizedOAuthMessageComponent(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let normalizedValue = value
            .replacingOccurrences(of: "+", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedValue.isEmpty else {
            return nil
        }

        return normalizedValue
    }

    func oauthDisplayMessage(
        errorCode: String?,
        errorDescription: String?,
        fallbackMessage: String? = nil
    ) -> String {
        oauthDisplayMessage(
            normalizedErrorCode: normalizedOAuthMessageComponent(errorCode),
            normalizedErrorDescription: normalizedOAuthMessageComponent(errorDescription),
            normalizedFallbackMessage: normalizedOAuthMessageComponent(fallbackMessage)
        )
    }

    func oauthDisplayMessage(
        normalizedErrorCode: String?,
        normalizedErrorDescription: String?,
        normalizedFallbackMessage: String? = nil
    ) -> String {
        if let normalizedErrorCode, let normalizedErrorDescription {
            return "\(normalizedErrorCode): \(normalizedErrorDescription)"
        }

        if let normalizedErrorDescription {
            return normalizedErrorDescription
        }

        if let normalizedErrorCode {
            return normalizedErrorCode
        }

        if let normalizedFallbackMessage {
            return normalizedFallbackMessage
        }

        return FronteggError.authError(.unknown).localizedDescription
    }

    func oauthFailureDetails(
        errorCode: String?,
        errorDescription: String?,
        fallbackError: FronteggError? = nil
    ) -> OAuthFailureDetails {
        oauthFailureDetails(
            normalizedErrorCode: normalizedOAuthMessageComponent(errorCode),
            normalizedErrorDescription: normalizedOAuthMessageComponent(errorDescription),
            fallbackError: fallbackError
        )
    }

    func oauthFailureDetails(
        normalizedErrorCode: String?,
        normalizedErrorDescription: String?,
        fallbackError: FronteggError? = nil
    ) -> OAuthFailureDetails {
        let message = oauthDisplayMessage(
            normalizedErrorCode: normalizedErrorCode,
            normalizedErrorDescription: normalizedErrorDescription,
            normalizedFallbackMessage: normalizedOAuthMessageComponent(
                fallbackError?.localizedDescription
            )
        )

        if normalizedErrorCode != nil || normalizedErrorDescription != nil {
            return OAuthFailureDetails(
                error: FronteggError.authError(.oauthError(message)),
                errorCode: normalizedErrorCode,
                errorDescription: normalizedErrorDescription
            )
        }

        return OAuthFailureDetails(
            error: fallbackError ?? FronteggError.authError(.oauthError(message)),
            errorCode: nil,
            errorDescription: nil
        )
    }

    func oauthFailureDetails(from queryItems: [String: String]) -> OAuthFailureDetails? {
        let errorCode = normalizedOAuthMessageComponent(queryItems["error"])
        let errorDescription = normalizedOAuthMessageComponent(queryItems["error_description"])

        guard errorCode != nil || errorDescription != nil else {
            return nil
        }

        return oauthFailureDetails(
            normalizedErrorCode: errorCode,
            normalizedErrorDescription: errorDescription
        )
    }

    func shouldSuppressOAuthErrorPresentation(for error: FronteggError) -> Bool {
        switch error {
        case .authError(let authError):
            switch authError {
            case .operationCanceled:
                return true
            case .other(let underlyingError):
                return Self.isUserCancelledOAuthFlow(underlyingError)
            default:
                return false
            }
        default:
            return false
        }
    }

    func reportOAuthFailure(
        error: FronteggError,
        flow: FronteggOAuthFlow,
        errorCode: String? = nil,
        errorDescription: String? = nil,
        embeddedMode: Bool? = nil
    ) {
        guard !shouldSuppressOAuthErrorPresentation(for: error) else {
            return
        }

        enqueueOAuthFailurePresentation(
            error: error,
            flow: flow,
            normalizedErrorCode: normalizedOAuthMessageComponent(errorCode),
            normalizedErrorDescription: normalizedOAuthMessageComponent(errorDescription),
            normalizedFallbackMessage: normalizedOAuthMessageComponent(error.localizedDescription),
            embeddedMode: embeddedMode
        )
    }

    func reportOAuthFailure(
        details: OAuthFailureDetails,
        flow: FronteggOAuthFlow,
        embeddedMode: Bool? = nil
    ) {
        guard !shouldSuppressOAuthErrorPresentation(for: details.error) else {
            return
        }

        enqueueOAuthFailurePresentation(
            error: details.error,
            flow: flow,
            normalizedErrorCode: details.errorCode,
            normalizedErrorDescription: details.errorDescription,
            normalizedFallbackMessage: normalizedOAuthMessageComponent(
                details.error.localizedDescription
            ),
            embeddedMode: embeddedMode
        )
    }

    func enqueueOAuthFailurePresentation(
        error: FronteggError,
        flow: FronteggOAuthFlow,
        normalizedErrorCode: String?,
        normalizedErrorDescription: String?,
        normalizedFallbackMessage: String?,
        embeddedMode: Bool?
    ) {
        let context = FronteggOAuthErrorContext(
            displayMessage: oauthDisplayMessage(
                normalizedErrorCode: normalizedErrorCode,
                normalizedErrorDescription: normalizedErrorDescription,
                normalizedFallbackMessage: normalizedFallbackMessage
            ),
            errorCode: normalizedErrorCode,
            errorDescription: normalizedErrorDescription,
            error: error,
            flow: flow,
            embeddedMode: embeddedMode ?? self.embeddedMode
        )
        let presentationMode = FronteggOAuthErrorRuntimeSettings.presentation
        let delegateBox = FronteggWeakOAuthErrorDelegateBox()
        delegateBox.value = FronteggOAuthErrorRuntimeSettings.delegateBox.value

        Task { @MainActor in
            FronteggRuntime.testingLog(
                "E2E queued OAuth error flow=\(context.flow) embedded=\(context.embeddedMode) code=\(context.errorCode ?? "nil") message=\(context.displayMessage)"
            )
            self.pendingOAuthErrorContext = context
            self.pendingOAuthErrorPresentationMode = presentationMode
            self.pendingOAuthErrorDelegateBox = delegateBox
            let shouldDeferEmbeddedPresentation = context.embeddedMode && self.webview != nil
            if shouldDeferEmbeddedPresentation {
                self.pendingOAuthErrorPresentationWorkItem?.cancel()
                self.pendingOAuthErrorPresentationWorkItem = nil
                self.scheduleEmbeddedOAuthErrorFallbackIfNeeded(for: context)
                return
            }

            self.pendingEmbeddedOAuthErrorFallbackWorkItem?.cancel()
            self.pendingEmbeddedOAuthErrorFallbackWorkItem = nil
            self.flushPendingOAuthErrorPresentationIfNeeded()
        }
    }

    @MainActor
    func flushPendingOAuthErrorPresentationIfNeeded(delayIfNeeded: Bool = false) {
        let presentationMode = pendingOAuthErrorPresentationMode ?? FronteggOAuthErrorRuntimeSettings.presentation
        let requiresForegroundWindow =
            presentationMode == .toast

        guard !requiresForegroundWindow || UIApplication.shared.applicationState != .background else {
            return
        }

        guard let context = pendingOAuthErrorContext else {
            pendingEmbeddedOAuthErrorFallbackWorkItem?.cancel()
            pendingEmbeddedOAuthErrorFallbackWorkItem = nil
            pendingOAuthErrorPresentationMode = nil
            pendingOAuthErrorDelegateBox = nil
            return
        }

        pendingEmbeddedOAuthErrorFallbackWorkItem?.cancel()
        pendingEmbeddedOAuthErrorFallbackWorkItem = nil
        let delegateBox = pendingOAuthErrorDelegateBox
        pendingOAuthErrorContext = nil
        pendingOAuthErrorPresentationMode = nil
        pendingOAuthErrorDelegateBox = nil
        FronteggRuntime.testingLog(
            "E2E flushing OAuth error flow=\(context.flow) embedded=\(context.embeddedMode) delay=\(delayIfNeeded)"
        )
        scheduleOAuthErrorPresentation(
            context,
            presentation: presentationMode,
            delegateBox: delegateBox,
            delay: delayIfNeeded ? oauthErrorPresentationDelay : 0
        )
    }

    @MainActor
    func scheduleOAuthErrorPresentation(
        _ context: FronteggOAuthErrorContext,
        presentation: FronteggOAuthErrorPresentation,
        delegateBox: FronteggWeakOAuthErrorDelegateBox?,
        delay: TimeInterval
    ) {
        pendingOAuthErrorPresentationWorkItem?.cancel()

        let shouldPresentImmediately =
            delay <= 0 && presentation == .delegate
        if shouldPresentImmediately {
            pendingOAuthErrorPresentationWorkItem = nil
            presentOAuthError(context, presentation: presentation, delegateBox: delegateBox)
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingOAuthErrorPresentationWorkItem = nil
            self.presentOAuthError(context, presentation: presentation, delegateBox: delegateBox)
        }

        pendingOAuthErrorPresentationWorkItem = workItem
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        } else {
            DispatchQueue.main.async(execute: workItem)
        }
    }

    @MainActor
    func scheduleEmbeddedOAuthErrorFallbackIfNeeded(for context: FronteggOAuthErrorContext) {
        pendingEmbeddedOAuthErrorFallbackWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingEmbeddedOAuthErrorFallbackWorkItem = nil
            guard let pendingContext = self.pendingOAuthErrorContext else {
                return
            }

            let isSamePendingError =
                pendingContext.displayMessage == context.displayMessage &&
                pendingContext.errorCode == context.errorCode &&
                pendingContext.errorDescription == context.errorDescription &&
                pendingContext.flow == context.flow &&
                pendingContext.embeddedMode == context.embeddedMode

            guard isSamePendingError else {
                return
            }

            self.logger.warning("Embedded OAuth error recovery did not settle in time. Presenting pending OAuth error and clearing the loader.")
            FronteggRuntime.testingLog(
                "E2E embedded OAuth error fallback firing flow=\(context.flow) code=\(context.errorCode ?? "nil")"
            )
            self.setWebLoading(false)
            self.flushPendingOAuthErrorPresentationIfNeeded()
        }

        pendingEmbeddedOAuthErrorFallbackWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + embeddedOAuthErrorRecoveryFallbackDelay,
            execute: workItem
        )
    }

    @MainActor
    func presentOAuthError(
        _ context: FronteggOAuthErrorContext,
        presentation: FronteggOAuthErrorPresentation,
        delegateBox: FronteggWeakOAuthErrorDelegateBox?
    ) {
        FronteggRuntime.testingLog(
            "E2E presenting OAuth error flow=\(context.flow) embedded=\(context.embeddedMode) message=\(context.displayMessage)"
        )
        switch presentation {
        case .toast:
            let window = self.resolveOAuthErrorPresentationWindow()
            if window == nil {
                self.logger.warning("OAuth failure toast could not find a presentation window")
            }
            FronteggOAuthToastPresenter.shared.show(message: context.displayMessage, in: window)
        case .delegate:
            delegateBox?.value?.fronteggSDK(didReceiveOAuthError: context)
        }
    }

    @MainActor
    func resolveOAuthErrorPresentationWindow() -> UIWindow? {
        if let window = self.webview?.window {
            return window
        }

        if let window = VCHolder.shared.vc?.presentedViewController?.view.window {
            return window
        }

        if let window = VCHolder.shared.vc?.view.window {
            return window
        }

        if let window = self.getRootVC(true)?.view.window {
            return window
        }

        if let window = self.getRootVC()?.view.window {
            return window
        }

        return UIWindow.fronteggPresentationCandidate
    }
}
