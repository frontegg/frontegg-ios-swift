//
//  WebSessionCookies.swift
//  FronteggSwift
//
//  The login box's web session cookies, kept in the embedded web view's cookie store.
//

import Foundation
import WebKit

protocol WebSessionCookieStoring {
    func refreshCookie(for host: String) async -> HTTPCookie?
    func store(_ cookies: [HTTPCookie]) async
}

final class WKWebSessionCookies: WebSessionCookieStoring {
    func refreshCookie(for host: String) async -> HTTPCookie? {
        let cookies = await allCookies()
        return cookies.first { $0.name.hasPrefix("fe_refresh") && Self.cookie($0, matches: host) }
    }

    func store(_ cookies: [HTTPCookie]) async {
        for cookie in cookies where cookie.name.hasPrefix("fe_refresh") || cookie.name.hasPrefix("fe_device") {
            await set(cookie)
        }
    }

    @MainActor
    private func allCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { continuation.resume(returning: $0) }
        }
    }

    @MainActor
    private func set(_ cookie: HTTPCookie) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            WKWebsiteDataStore.default().httpCookieStore.setCookie(cookie) { continuation.resume() }
        }
    }

    static func cookie(_ cookie: HTTPCookie, matches host: String) -> Bool {
        let domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
        return domain == host || host.hasSuffix(".\(domain)") || domain.hasSuffix(".\(host)")
    }
}
