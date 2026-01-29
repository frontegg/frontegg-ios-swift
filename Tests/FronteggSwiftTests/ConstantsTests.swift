//
//  ConstantsTests.swift
//  FronteggSwiftTests
//

import XCTest
@testable import FronteggSwift

final class ConstantsTests: XCTestCase {

    // MARK: - URLConstants

    func test_successLoginRoutes_containsSocialSuccess() {
        XCTAssertTrue(URLConstants.successLoginRoutes.contains("/oauth/account/social/success"))
    }

    func test_loginRoutes_containsOAuthAccount() {
        XCTAssertTrue(URLConstants.loginRoutes.contains("/oauth/account/"))
    }

    func test_generateSocialLoginRedirectUri_returnsCorrectFormat() {
        let baseUrl = "https://auth.example.com"
        let redirect = URLConstants.generateSocialLoginRedirectUri(baseUrl)
        XCTAssertEqual(redirect, "https://auth.example.com/oauth/account/social/success")
    }

    // MARK: - StepUpConstants

    func test_stepUpConstants_ACR_VALUE() {
        XCTAssertEqual(StepUpConstants.ACR_VALUE, "http://schemas.openid.net/pape/policies/2007/06/multi-factor")
    }

    func test_stepUpConstants_AMR_MFA_VALUE() {
        XCTAssertEqual(StepUpConstants.AMR_MFA_VALUE, "mfa")
    }

    func test_stepUpConstants_AMR_ADDITIONAL_VALUE() {
        XCTAssertEqual(StepUpConstants.AMR_ADDITIONAL_VALUE, ["otp", "sms", "hwk"])
    }

    func test_stepUpConstants_STEP_UP_MAX_AGE_PARAM_NAME() {
        XCTAssertEqual(StepUpConstants.STEP_UP_MAX_AGE_PARAM_NAME, "maxAge")
    }
}
