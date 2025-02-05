//
//  AppleAuthenticatorTests.swift
//  FronteggSwift
//
//  Created by Oleksii Minaiev on 04.02.2025.
//


import XCTest
import AuthenticationServices
@testable import FronteggSwift

@available(iOS 15.0, *)
class AppleAuthenticatorTests: XCTestCase {
    func test_init_doesNotPerformRequests() {
        let (_, controller) = makeSUT()
        XCTAssertEqual(controller.performRequestsCallCount, 0)
    }
    
    func test_authenticate_performsRequestOnce() {
        let (sut, controller) = makeSUT()
        sut.start()
        XCTAssertEqual(controller.performRequestsCallCount, 1)
    }
    
    func test_authenticate_receivedRequests() {
        let (sut, controler) = makeSUT()
        sut.start()
        XCTAssertEqual(controler.requests.count, 1)
        XCTAssertTrue(controler.requests.first is ASAuthorizationAppleIDRequest)
        XCTAssertEqual((controler.requests.first as? ASAuthorizationAppleIDRequest)?.requestedScopes,  [.fullName, .email])
        XCTAssertEqual((controler.requests.first as? ASAuthorizationAppleIDRequest)?.requestedOperation,  .operationLogin)
    }
    
    func test_authenticate_setsDelegate() {
        let (sut, controller) = makeSUT()
        sut.start()
        XCTAssertTrue(controller.delegate === sut)
    }
    
    func test_didCompleteWithError_firesDelegateMethodWithError() {
        let expectation = self.expectation(description: "Completion handler should be called on failure")
        
        let delegate: AppleAuthenticator.Delegate = {result in
            switch result {
            case .success:
                XCTFail( "Authentication should not happened")
            case .failure:
                XCTAssertTrue(true, "Authentication should not fail in this test case")
                
                expectation.fulfill()
            }
        }
        
        let (sut, controller) = makeSUT(delegate: delegate)
        let anyError = NSError(domain: "", code: 0, userInfo: nil)
        
        sut.authorizationController(controller: controller, didCompleteWithError: anyError)
        
        waitForExpectations(timeout: 2)
    }
    
    func test_completeWithCredential_withInvalidToken_firesDelegateMethodWithInvalidCredentialsError() {
        let expectation = self.expectation(description: "Completion handler should be called on failure")
        
        let delegate: AppleAuthenticator.Delegate = {result in
            switch result {
            case .success:
                XCTFail( "Authentication should not happened")
            case .failure:
                XCTAssertTrue(true, "Authentication should not fail in this test case")
                expectation.fulfill()
            }
        }
        
        let (sut, _) = makeSUT(delegate: delegate)
        
        sut.completeWith(credential: Credential(authorizationCode: nil))
        waitForExpectations(timeout: 2)
    }
    
    func test_completeWithCredential_withValidToken_firesDelegateMethodWithToken() {
        let expectation = self.expectation(description: "Completion handler should be called on success")
        
        let delegate: AppleAuthenticator.Delegate = {result in
            switch result {
            case .success:
                XCTAssertTrue(true, "Authentication should happened")
                expectation.fulfill()
            case .failure:
                XCTAssertTrue(true, "Authentication should fail in this test case")
                
            }
        }
        
        let (sut, _) = makeSUT(delegate: delegate)
        sut.completeWith(credential: Credential(authorizationCode: Data("any code".utf8)))
        
        waitForExpectations(timeout: 2)
    }
    
    private func makeSUT(file: StaticString = #filePath, line: UInt = #line, delegate: AppleAuthenticator.Delegate? = nil) -> (AppleAuthenticator, ASAuthorizationController.Spy) {
        let controller = ASAuthorizationController.spy
        let innerDelegate: AppleAuthenticator.Delegate = {result in
            switch result {
            case .success:
                print("Success")
            case .failure:
                print("Failure")
            }
        }
        
        let factory: AppleAuthenticator.ControllerFactory = { requests in
            controller.requests.append(contentsOf: requests)
            return controller
        }
        
        let sut = AppleAuthenticator(
            delegate: delegate ?? innerDelegate,
            factory: factory
        )
        
        trackForMemoryLeaks(controller, file: file, line: line)
        trackForMemoryLeaks(sut, file: file, line: line)
        return (sut, controller)
    }
    
    private func trackForMemoryLeaks(_ instance: AnyObject, file: StaticString = #file, line: UInt = #line) {
        addTeardownBlock { [weak instance] in
            XCTAssertNil(instance, file: file, line: line)
        }
    }
}

extension ASAuthorizationController {
    
    static var spy: Spy {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        return Spy(authorizationRequests: [request])
    }
    
    class Spy: ASAuthorizationController {
        
        var performRequestsCallCount = 0
        var requests: [ASAuthorizationRequest] = []
        
        override func performRequests() {
            performRequestsCallCount += 1
        }
    }
}

private struct Credential: AppleIDCredential {
    var authorizationCode: Data?
}
