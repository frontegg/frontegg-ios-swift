//
//  FronteggAuth+AdminPortalSession.swift
//  FronteggSwift
//
//  Coordinates the "baton handoff" of the refresh-token rotation chain between
//  the SDK's background refresh loop and the embedded admin portal WebView.
//
//  Why this exists — the core problem, proven against the auth backend:
//  The Frontegg refresh token is a SINGLE-USE, ROTATING credential with NO
//  grace window. Every read of it (the SDK's `/.../user/token/refresh`, the
//  portal's `/oauth/authorize/silent`, etc.) consumes it and the server issues
//  a fresh one; the previous value dies instantly. The SDK runs a background
//  refresh loop AND the portal WebView needs the same credential. If both
//  touch it, they invalidate each other:
//    * SDK refreshes → the portal's cookie goes stale → portal bounces to login
//      (the original "second login", worst on cold start where the loop fires
//      immediately).
//    * Portal refreshes → the SDK's stored token goes stale → the SDK logs the
//      user out on its next refresh.
//
//  The handoff: while the portal is open it is the SOLE consumer. The SDK
//  pauses its auto-refresh, hands the portal its current token, and when the
//  portal closes the SDK reclaims whatever token the portal last rotated to
//  (read back from the WebView cookie store) and resumes.
//
//  Residual risk (documented, accepted for the beta): if the app is killed
//  while the portal is open, the reclaim never runs, so the SDK's stored token
//  is stale on next launch and the user re-authenticates once. That is no
//  worse than today's behavior (re-login every portal open) and only on a
//  hard-kill-mid-portal.
//

import Foundation

extension FronteggAuth {

    /// Begin an admin-portal session: pause the SDK's auto-refresh loop and
    /// return the current refresh token for the portal WebView to use.
    ///
    /// Returns nil if there is no refresh token (user not authenticated) — the
    /// caller should then just load the portal, which will render its own
    /// login.
    @MainActor
    func beginAdminPortalSession() -> String? {
        logger.info("AdminPortalSession: begin — pausing SDK auto-refresh so the portal owns the token chain")
        adminPortalSessionActive = true
        // Cancel any scheduled refresh. (An already-in-flight refresh — a sub-
        // second window that recurs ~once per token TTL — could still rotate
        // the token we return; that race degrades to the portal showing its
        // own login, the pre-existing behavior, and self-heals on reclaim.)
        cancelScheduledTokenRefresh()
        let token = self.refreshToken
        logger.info("AdminPortalSession: handed portal a refresh token (present: \(token != nil))")
        return token
    }

    /// End an admin-portal session: reclaim the (possibly rotated) refresh
    /// token the portal last used, make the SDK adopt it, and resume the
    /// auto-refresh loop.
    ///
    /// - Parameter reclaimedRefreshToken: the latest `fe_refresh_*` cookie
    ///   value read back from the portal WebView's cookie store, or nil if the
    ///   caller couldn't read one (in which case the SDK falls back to its
    ///   existing stored token and resumes the loop).
    func endAdminPortalSession(reclaimedRefreshToken: String?) async {
        logger.info("AdminPortalSession: end — reclaiming token (present: \(reclaimedRefreshToken != nil)) and resuming auto-refresh")

        // Clear the suppression flag FIRST so the normal refresh paths below
        // (and any future auto-refresh) are no longer blocked.
        await MainActor.run { self.adminPortalSessionActive = false }

        guard let reclaimed = reclaimedRefreshToken, !reclaimed.isEmpty else {
            // Nothing to reclaim — resume from whatever the SDK already has.
            // It may be stale (the portal may have rotated past it), in which
            // case the SDK's normal refresh-failure handling (retry / offline /
            // re-auth) takes over. We don't make it worse.
            logger.info("AdminPortalSession: no reclaimed token — resuming loop from existing stored token")
            await resumeAutoRefreshAfterPortal()
            return
        }

        // Convert the reclaimed refresh token into a full credential set using
        // the SDK's existing, tested refresh path (which picks the right
        // endpoint for tenant vs non-tenant configs), then inject it via
        // setCredentials (which persists to keychain with correct tenant
        // scoping, updates published state, and reschedules the next refresh).
        // We deliberately do NOT hand-write the keychain here.
        do {
            let tenantId = resolveAdminPortalReclaimTenantId()
            let authResponse = try await self.api.refreshToken(
                refreshToken: reclaimed,
                tenantId: tenantId
            )
            await self.setCredentials(
                accessToken: authResponse.access_token,
                refreshToken: authResponse.refresh_token
            )
            logger.info("AdminPortalSession: reclaimed token adopted; SDK session resumed")
        } catch {
            // Reclaim refresh failed (network blip, or the reclaimed token was
            // already consumed by an in-portal call we didn't observe). Resume
            // the loop from the existing stored token and let normal failure
            // handling recover.
            logger.warning("AdminPortalSession: reclaim refresh failed (\(error.localizedDescription)); resuming loop from existing stored token")
            await resumeAutoRefreshAfterPortal()
        }
    }

    /// Tenant id to scope the reclaim refresh to, mirroring how the SDK's own
    /// refresh decides: only when per-tenant sessions are enabled.
    private func resolveAdminPortalReclaimTenantId() -> String? {
        let enableSessionPerTenant = (try? PlistHelper.fronteggConfig())?.enableSessionPerTenant ?? false
        guard enableSessionPerTenant else { return nil }
        return self.user?.activeTenant.tenantId
    }

    /// Resume the auto-refresh loop after a portal session without a usable
    /// reclaim. Triggers a normal refresh attempt; the internal scheduler takes
    /// over from there.
    private func resumeAutoRefreshAfterPortal() async {
        _ = await refreshTokenIfNeededInternal(source: .manualUser)
    }
}
