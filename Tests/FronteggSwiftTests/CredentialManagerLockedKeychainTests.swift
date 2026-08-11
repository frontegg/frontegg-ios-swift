import XCTest
@testable import FronteggSwift

final class CredentialManagerLockedKeychainTests: XCTestCase {

    private func manager(returning status: OSStatus) -> CredentialManager {
        let manager = CredentialManager(serviceKey: "fr26384-tests")
        manager.copyMatching = { _, _ in status }
        return manager
    }

    func testMissingItemIsReportedAsMissing() {
        let manager = manager(returning: errSecItemNotFound)

        do {
            _ = try manager.get(key: KeychainKeys.refreshToken.rawValue)
            XCTFail("expected a missing item to throw")
        } catch let error as CredentialManager.KeychainError {
            switch error {
            case .unknown(let status):
                XCTAssertEqual(status, errSecItemNotFound)
            default:
                XCTFail("unexpected error \(error)")
            }
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testLockedKeychainIsNotReportedAsAnOpaqueFailure() {
        let manager = manager(returning: errSecInteractionNotAllowed)

        do {
            _ = try manager.get(key: KeychainKeys.refreshToken.rawValue)
            XCTFail("expected a locked keychain to throw")
        } catch let error as CredentialManager.KeychainError {
            switch error {
            case .unknown(let status):
                XCTFail("locked keychain surfaced as unknown(\(status)), indistinguishable from a missing token")
            default:
                break
            }
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }
}
