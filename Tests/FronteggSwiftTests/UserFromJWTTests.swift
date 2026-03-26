//
//  UserFromJWTTests.swift
//  FronteggSwiftTests
//
//  Tests for User.fromJWT() — building a minimal User from JWT access token claims.

import XCTest
@testable import FronteggSwift

final class UserFromJWTTests: XCTestCase {

    // MARK: - Test Data

    /// Realistic JWT claims based on a real Frontegg access token.
    private func makeValidClaims() -> [String: Any] {
        return [
            "sub": "75c8b6ce-b640-40ab-b2cb-20f251d6c4d0",
            "name": "David Antoon",
            "email": "david+2@frontegg.com",
            "email_verified": true,
            "metadata": ["name": "David Antoon", "jobTitle": "Mr"],
            "roles": ["Admin"],
            "permissions": ["fe.subscriptions.*", "fe.secure.*", "fe.connectivity.*"],
            "tenantId": "9023b0ab-47f4-44a0-a683-34d7cfa6f989",
            "tenantIds": [
                "4703713d-4d49-4ba2-99eb-6d8d68f1fc1f",
                "9023b0ab-47f4-44a0-a683-34d7cfa6f989"
            ],
            "profilePictureUrl": "https://cdn.frontegg.com/profile/pic.jpeg",
            "externalId": NSNull(),
            "phoneNumber": NSNull(),
            "type": "userToken",
            "aud": "b6adfe4c-d695-4c04-b95f-3ec9fd0c6cca",
            "iss": "https://autheu.davidantoon.me",
            "iat": 1774459806,
            "exp": 1774459866
        ]
    }

    // MARK: - Valid Payload

    func test_fromJWT_validPayload_returnsUser() {
        let claims = makeValidClaims()
        let user = User.fromJWT(claims)

        XCTAssertNotNil(user)
        XCTAssertEqual(user?.id, "75c8b6ce-b640-40ab-b2cb-20f251d6c4d0")
        XCTAssertEqual(user?.name, "David Antoon")
        XCTAssertEqual(user?.email, "david+2@frontegg.com")
        XCTAssertEqual(user?.tenantId, "9023b0ab-47f4-44a0-a683-34d7cfa6f989")
        XCTAssertEqual(user?.verified, true)
        XCTAssertEqual(user?.profilePictureUrl, "https://cdn.frontegg.com/profile/pic.jpeg")
    }

    func test_fromJWT_validPayload_buildsSyntheticTenants() {
        let claims = makeValidClaims()
        let user = User.fromJWT(claims)!

        XCTAssertEqual(user.tenants.count, 2)
        XCTAssertEqual(user.tenantIds.count, 2)
        XCTAssertEqual(user.activeTenant.id, "9023b0ab-47f4-44a0-a683-34d7cfa6f989")
        XCTAssertEqual(user.tenants[0].id, "4703713d-4d49-4ba2-99eb-6d8d68f1fc1f")
        XCTAssertEqual(user.tenants[1].id, "9023b0ab-47f4-44a0-a683-34d7cfa6f989")
    }

    func test_fromJWT_validPayload_buildsSyntheticRoles() {
        let claims = makeValidClaims()
        let user = User.fromJWT(claims)!

        XCTAssertEqual(user.roles.count, 1)
        XCTAssertEqual(user.roles[0].key, "Admin")
        XCTAssertEqual(user.roles[0].name, "Admin")
    }

    func test_fromJWT_validPayload_buildsSyntheticPermissions() {
        let claims = makeValidClaims()
        let user = User.fromJWT(claims)!

        XCTAssertEqual(user.permissions.count, 3)
        XCTAssertEqual(user.permissions[0].key, "fe.subscriptions.*")
        XCTAssertEqual(user.permissions[1].key, "fe.secure.*")
        XCTAssertEqual(user.permissions[2].key, "fe.connectivity.*")
    }

    // MARK: - Missing Required Fields

    func test_fromJWT_missingSub_returnsNil() {
        var claims = makeValidClaims()
        claims.removeValue(forKey: "sub")

        XCTAssertNil(User.fromJWT(claims))
    }

    func test_fromJWT_missingName_fallsBackToEmail() {
        var claims = makeValidClaims()
        claims.removeValue(forKey: "name")

        let user = User.fromJWT(claims)
        XCTAssertNotNil(user)
        XCTAssertEqual(user?.name, "david+2@frontegg.com")
    }

    func test_fromJWT_missingEmail_fallsBackToPreferredUsername() {
        var claims = makeValidClaims()
        claims.removeValue(forKey: "email")
        claims["preferred_username"] = "preferred@example.com"

        let user = User.fromJWT(claims)
        XCTAssertNotNil(user)
        XCTAssertEqual(user?.email, "preferred@example.com")
        XCTAssertEqual(user?.name, "David Antoon")
    }

    func test_fromJWT_missingTenantId_fallsBackToTenantIds() {
        var claims = makeValidClaims()
        claims.removeValue(forKey: "tenantId")

        let user = User.fromJWT(claims)
        XCTAssertNotNil(user)
        XCTAssertEqual(user?.tenantId, "4703713d-4d49-4ba2-99eb-6d8d68f1fc1f")
    }

    // MARK: - Optional Fields

    func test_fromJWT_noRoles_returnsUserWithEmptyRoles() {
        var claims = makeValidClaims()
        claims.removeValue(forKey: "roles")

        let user = User.fromJWT(claims)
        XCTAssertNotNil(user)
        XCTAssertEqual(user?.roles.count, 0)
    }

    func test_fromJWT_noPermissions_returnsUserWithEmptyPermissions() {
        var claims = makeValidClaims()
        claims.removeValue(forKey: "permissions")

        let user = User.fromJWT(claims)
        XCTAssertNotNil(user)
        XCTAssertEqual(user?.permissions.count, 0)
    }

    func test_fromJWT_noTenantIds_defaultsToSingleTenant() {
        var claims = makeValidClaims()
        claims.removeValue(forKey: "tenantIds")

        let user = User.fromJWT(claims)
        XCTAssertNotNil(user)
        XCTAssertEqual(user?.tenants.count, 1)
        XCTAssertEqual(user?.tenants[0].id, "9023b0ab-47f4-44a0-a683-34d7cfa6f989")
    }

    func test_fromJWT_noProfilePicture_defaultsToEmpty() {
        var claims = makeValidClaims()
        claims.removeValue(forKey: "profilePictureUrl")

        let user = User.fromJWT(claims)
        XCTAssertNotNil(user)
        XCTAssertEqual(user?.profilePictureUrl, "")
    }

    func test_fromJWT_emailVerifiedFalse() {
        var claims = makeValidClaims()
        claims["email_verified"] = false

        let user = User.fromJWT(claims)
        XCTAssertNotNil(user)
        XCTAssertEqual(user?.verified, false)
    }

    func test_fromJWT_noEmailVerified_defaultsToFalse() {
        var claims = makeValidClaims()
        claims.removeValue(forKey: "email_verified")

        let user = User.fromJWT(claims)
        XCTAssertNotNil(user)
        XCTAssertEqual(user?.verified, false)
    }

    func test_fromJWT_usesAlternateTenantAndProfileClaims() {
        var claims = makeValidClaims()
        claims.removeValue(forKey: "tenantId")
        claims["tenant_id"] = "tenant-alt"
        claims.removeValue(forKey: "profilePictureUrl")
        claims["picture"] = "https://example.com/picture.png"

        let user = User.fromJWT(claims)
        XCTAssertNotNil(user)
        XCTAssertEqual(user?.tenantId, "tenant-alt")
        XCTAssertEqual(user?.profilePictureUrl, "https://example.com/picture.png")
    }

    func test_fromJWT_stringifiesMetadataObjects() {
        let user = User.fromJWT(makeValidClaims())

        XCTAssertNotNil(user?.metadata)
        XCTAssertTrue(user?.metadata?.contains("\"jobTitle\":\"Mr\"") == true)
    }

    // MARK: - Real JWT Decode Round-Trip

    func test_fromJWT_realJWTDecode_roundTrip() {
        // Decode a real JWT token (from the user's sample)
        let jwt = "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6ImI2YWRmZTRjIn0.eyJzdWIiOiI3NWM4YjZjZS1iNjQwLTQwYWItYjJjYi0yMGYyNTFkNmM0ZDAiLCJuYW1lIjoiRGF2aWQgQW50b29uIiwiZW1haWwiOiJkYXZpZCsyQGZyb250ZWdnLmNvbSIsImVtYWlsX3ZlcmlmaWVkIjp0cnVlLCJtZXRhZGF0YSI6eyJuYW1lIjoiRGF2aWQgQW50b29uIiwiam9iVGl0bGUiOiJNciJ9LCJyb2xlcyI6WyJBZG1pbiJdLCJwZXJtaXNzaW9ucyI6WyJmZS5zdWJzY3JpcHRpb25zLioiLCJmZS5hY2NvdW50LXNldHRpbmdzLmRlbGV0ZS5hY2NvdW50IiwiZmUuc2VjdXJlLioiLCJmZS5hY2NvdW50LXNldHRpbmdzLndyaXRlLmN1c3RvbS1sb2dpbi1ib3giLCJmZS5jb25uZWN0aXZpdHkuKiIsImZlLmFjY291bnQtaGllcmFyY2h5LndyaXRlLnN1YkFjY291bnRBY2Nlc3MiLCJmZS5hY2NvdW50LWhpZXJhcmNoeS5yZWFkLnN1YkFjY291bnQiLCJmZS5hY2NvdW50LWhpZXJhcmNoeS5kZWxldGUuc3ViQWNjb3VudCIsImZlLmFjY291bnQtaGllcmFyY2h5LndyaXRlLnN1YkFjY291bnQiLCJmZS5hY2NvdW50LXNldHRpbmdzLnJlYWQuYXBwIl0sInRlbmFudElkIjoiOTAyM2IwYWItNDdmNC00NGEwLWE2ODMtMzRkN2NmYTZmOTg5IiwidGVuYW50SWRzIjpbIjQ3MDM3MTNkLTRkNDktNGJhMi05OWViLTZkOGQ2OGYxZmMxZiIsIjkwMjNiMGFiLTQ3ZjQtNDRhMC1hNjgzLTM0ZDdjZmE2Zjk4OSJdLCJwcm9maWxlUGljdHVyZVVybCI6Imh0dHBzOi8vY2RuLmZyb250ZWdnLmNvbS9wdWJsaWMtdmVuZG9yLWFzc2V0cy9iNmFkZmU0Yy1kNjk1LTRjMDQtYjk1Zi0zZWM5ZmQwYzZjY2EvcHJvZmlsZS83NWM4YjZjZS1iNjQwLTQwYWItYjJjYi0yMGYyNTFkNmM0ZDAtMTcyMzI0MDc0NTQ2OS5qcGVnP3Q9MTcyMzI0MDc0NTczNSIsImV4dGVybmFsSWQiOm51bGwsInBob25lTnVtYmVyIjpudWxsLCJzaWQiOiI3NTI3NDE5Zi05NTc3LTRmMDctOGEwMi02MTdkNDFiMTIwYmUiLCJ0eXBlIjoidXNlclRva2VuIiwiYXBwbGljYXRpb25JZCI6IjYwYjcxZDVkLTI1YTQtNGQwZS1iNjYwLWM1MDVhZGFkNjdjYiIsImF1ZCI6ImI2YWRmZTRjLWQ2OTUtNGMwNC1iOTVmLTNlYzlmZDBjNmNjYSIsImlzcyI6Imh0dHBzOi8vYXV0aGV1LmRhdmlkYW50b29uLm1lIiwiaWF0IjoxNzc0NDU5ODA2LCJleHAiOjE3NzQ0NTk4NjZ9.FaAqiMc6yiwWel0-hL9XcBltNJDnNqP2meBL0ORWU0F1iJwKEFsQmJC7Ikv8feDtbc90N-8byjdfLUxS79Ix4n0wsoT9vi0UWlsJM9bXDAL0UwKMhq0Re5E6E-cgnII1IJ4za52hnWvbw6b2HXfvfvWokW624t7F_5q8xpmxWRIqc4Rp3tEwSKzh5gRAqPrn0IRdPwViyKI7rzdqof74cusJO3R0_2ow2dUuN-CPA-HHnfZhfhMractZC-G1aEX5lukAw7h3oTg_qzBRFcWAH001pWw6x5VejB_5MkOXnG2nerz373RK4d9mgsyJh6fF9JCZUfU4Yzkm1qvQ7_navQ"

        guard let claims = try? JWTHelper.decode(jwtToken: jwt) else {
            XCTFail("Failed to decode JWT")
            return
        }

        let user = User.fromJWT(claims)
        XCTAssertNotNil(user, "User.fromJWT should succeed with real JWT claims")
        XCTAssertEqual(user?.id, "75c8b6ce-b640-40ab-b2cb-20f251d6c4d0")
        XCTAssertEqual(user?.name, "David Antoon")
        XCTAssertEqual(user?.email, "david+2@frontegg.com")
        XCTAssertEqual(user?.tenantId, "9023b0ab-47f4-44a0-a683-34d7cfa6f989")
        XCTAssertEqual(user?.tenantIds.count, 2)
        XCTAssertEqual(user?.tenants.count, 2)
        XCTAssertEqual(user?.roles.count, 1)
        XCTAssertEqual(user?.roles.first?.key, "Admin")
        XCTAssertEqual(user?.permissions.count, 10)
        XCTAssertEqual(user?.verified, true)
    }
}
