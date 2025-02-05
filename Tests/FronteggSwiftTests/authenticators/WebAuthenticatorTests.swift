//
//  WebAuthenticatorTests.swift
//  FronteggSwift
//
//  Created by Oleksii Minaiev on 05.02.2025.
//

import XCTest
import AuthenticationServices

@testable import FronteggSwift

class WebAuthenticatorTests: XCTestCase {
    private let url: URL = URLComponents(string: "https://appleid.apple.com/auth/authorize")!.url!
    private let emptyCompletionHandler: ASWebAuthenticationSession.CompletionHandler = { callbackUrl, error in}
    private let mockFronteggInnerStorage: FronteggInnerStorage = MockFronteggInnerStorage()
    
    func test_init_doesNotPerformStart() {
        let (_, session) = makeSUT()
        XCTAssertEqual(session.performStartCallCount, 0)
    }
    
    func test_authenticate_performsStartOnce() {
        let (sut, session) = makeSUT()
        sut.start(
            url,
            completionHandler:emptyCompletionHandler
        )
        XCTAssertEqual(session.performStartCallCount, 1)
    }
    
    func test_authenticate_receivedRequest() {
        let (sut, session) = makeSUT(storage: mockFronteggInnerStorage)
        
        sut.start(
            url,
            ephemeralSession: true,
            completionHandler: emptyCompletionHandler
        )
        
        XCTAssertEqual(session.url, url)
        XCTAssertEqual(session.prefersEphemeralWebBrowserSession, true)
        XCTAssertEqual(session.callbackURLScheme, mockFronteggInnerStorage.bundleIdentifier)
    }
    
    func test_WebAuthenticatorSaveSession() {
        let (sut, session) = makeSUT()
        
        sut.start(
            url,
            completionHandler: emptyCompletionHandler
        )
        
        XCTAssertEqual(sut.session, session)
    }
    
    private func makeSUT(file: StaticString = #filePath, line: UInt = #line, storage: FronteggInnerStorage? = nil) -> (WebAuthenticator, ASWebAuthenticationSession.Spy) {
        let session = ASWebAuthenticationSession.spy
        
        let factory: WebAuthenticator.WebAuthenticationSessionFactory = { url, callbackURLScheme, completionHandler in
            session.url = url
            session.callbackURLScheme = callbackURLScheme
            session.completionHandler = completionHandler
            return session
        }
        
        let sut = WebAuthenticator(
            storage: storage ?? FronteggInnerStorage.shared,
            factory: factory
        )
        
        trackForMemoryLeaks(session, file: file, line: line)
        trackForMemoryLeaks(sut, file: file, line: line)
        return (sut, session)
    }
    
    private func trackForMemoryLeaks(_ instance: AnyObject, file: StaticString = #file, line: UInt = #line) {
        addTeardownBlock { [weak instance] in
            XCTAssertNil(instance, file: file, line: line)
        }
    }
}

class MockFronteggInnerStorage: FronteggInnerStorage {
    override init() {
        super.init()
        self.bundleIdentifier = "com.frontegg.demo"
    }
}

extension ASWebAuthenticationSession {
    
    static var spy: Spy {
        let urlComponent = URLComponents(string: "https://appleid.apple.com/auth/authorize")!
        let callback: ASWebAuthenticationSession.CompletionHandler = { callbackUrl, error in}
        
        return Spy(
            url: urlComponent.url!,
            callbackURLScheme: "com.frontegg.demo",
            completionHandler: callback
        )
    }
    
    class Spy: ASWebAuthenticationSession {
        var url: URL = URLComponents(string: "https://appleid.apple.com/auth/authorize")!.url!
        var callbackURLScheme: String? = "com.frontegg.demo"
        var completionHandler: ASWebAuthenticationSession.CompletionHandler? = nil

        var performStartCallCount = 0
        override func start() -> Bool {
            self.performStartCallCount += 1
            return true
        }
    }
}
