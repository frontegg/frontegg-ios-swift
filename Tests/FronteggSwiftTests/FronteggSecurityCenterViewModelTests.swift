import XCTest
import Combine
@testable import FronteggSwift

@MainActor
final class FronteggSecurityCenterViewModelTests: XCTestCase {

    private final class MockService: FronteggSecurityCenterService {
        var sessionsResult: Result<[FronteggSession], Error> = .success([])
        var passkeysResult: Result<[FronteggPasskey], Error> = .success([])
        var actionError: Error?
        var steppedUp = false

        var listSessionsCalls = 0
        var listPasskeysCalls = 0
        var revokedSessionIds: [String] = []
        var revokeOtherSessionsCalls = 0
        var deletedPasskeyIds: [String] = []
        var registerPasskeyCalls = 0
        var stepUpMaxAges: [TimeInterval?] = []

        func listSessions() async throws -> [FronteggSession] {
            listSessionsCalls += 1
            return try sessionsResult.get()
        }

        func revokeSession(id: String) async throws {
            revokedSessionIds.append(id)
            if let actionError { throw actionError }
        }

        func revokeOtherSessions() async throws {
            revokeOtherSessionsCalls += 1
            if let actionError { throw actionError }
        }

        func listPasskeys() async throws -> [FronteggPasskey] {
            listPasskeysCalls += 1
            return try passkeysResult.get()
        }

        func deletePasskey(id: String) async throws {
            deletedPasskeyIds.append(id)
            if let actionError { throw actionError }
        }

        func registerPasskey() async throws {
            registerPasskeyCalls += 1
            if let actionError { throw actionError }
        }

        func stepUp(maxAge: TimeInterval?) async throws {
            stepUpMaxAges.append(maxAge)
            if let actionError { throw actionError }
            steppedUp = true
        }

        func isSteppedUp(maxAge: TimeInterval?) -> Bool {
            steppedUp
        }
    }

    private var service: MockService!
    private var userSubject: CurrentValueSubject<User?, Never>!

    override func setUp() async throws {
        try await super.setUp()
        service = MockService()
        userSubject = CurrentValueSubject(nil)
    }

    private func makeViewModel(stepUpMaxAge: TimeInterval? = nil) -> FronteggSecurityCenterViewModel {
        FronteggSecurityCenterViewModel(
            service: service,
            userPublisher: userSubject.eraseToAnyPublisher(),
            stepUpMaxAge: stepUpMaxAge
        )
    }

    private func makeUser(mfaEnrolled: Bool, tenantName: String = "Acme") throws -> User {
        let tenant = TestDataFactory.makeTenant(id: "t1", name: tenantName, tenantId: "t1")
        let data = try TestDataFactory.jsonData(from: TestDataFactory.makeUser(
            mfaEnrolled: mfaEnrolled,
            tenantId: "t1",
            tenantIds: ["t1"],
            tenants: [tenant],
            activeTenant: tenant
        ))
        return try JSONDecoder().decode(User.self, from: data)
    }

    func testLoadFetchesSessionsAndPasskeysWithCurrentSessionFirst() async {
        service.sessionsResult = .success([
            FronteggSession(id: "other", isCurrent: false),
            FronteggSession(id: "mine", isCurrent: true)
        ])
        service.passkeysResult = .success([FronteggPasskey(id: "pk1", deviceType: .platform)])
        let viewModel = makeViewModel()

        await viewModel.load()

        XCTAssertEqual(viewModel.sessions.map(\.id), ["mine", "other"])
        XCTAssertEqual(viewModel.passkeys.map(\.id), ["pk1"])
        XCTAssertFalse(viewModel.isLoadingSessions)
        XCTAssertFalse(viewModel.isLoadingPasskeys)
        XCTAssertNil(viewModel.sessionsError)
        XCTAssertNil(viewModel.passkeysError)
        XCTAssertEqual(viewModel.otherSessions.map(\.id), ["other"])
    }

    func testSessionLoadFailureIsSurfacedPerSectionWithoutBlockingPasskeys() async {
        service.sessionsResult = .failure(FronteggSecurityCenterError.requestFailed(statusCode: 500))
        service.passkeysResult = .success([FronteggPasskey(id: "pk1", deviceType: .platform)])
        let viewModel = makeViewModel()

        await viewModel.load()

        XCTAssertNotNil(viewModel.sessionsError)
        XCTAssertTrue(viewModel.sessions.isEmpty)
        XCTAssertNil(viewModel.passkeysError)
        XCTAssertEqual(viewModel.passkeys.map(\.id), ["pk1"])
    }

    func testPasskeyLoadFailureIsSurfaced() async {
        service.passkeysResult = .failure(FronteggSecurityCenterError.requestFailed(statusCode: 403))
        let viewModel = makeViewModel()

        await viewModel.load()

        XCTAssertEqual(viewModel.passkeysError, FronteggSecurityCenterError.requestFailed(statusCode: 403).localizedDescription)
    }

    func testRevokeSessionCallsServiceAndReloads() async {
        service.sessionsResult = .success([
            FronteggSession(id: "mine", isCurrent: true),
            FronteggSession(id: "other", isCurrent: false)
        ])
        let viewModel = makeViewModel()
        await viewModel.load()
        service.sessionsResult = .success([FronteggSession(id: "mine", isCurrent: true)])

        await viewModel.revoke(FronteggSession(id: "other", isCurrent: false))

        XCTAssertEqual(service.revokedSessionIds, ["other"])
        XCTAssertEqual(viewModel.sessions.map(\.id), ["mine"])
        XCTAssertEqual(service.listSessionsCalls, 2)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.pendingIds.isEmpty)
    }

    func testRevokeCurrentSessionIsRefused() async {
        let viewModel = makeViewModel()

        await viewModel.revoke(FronteggSession(id: "mine", isCurrent: true))

        XCTAssertTrue(service.revokedSessionIds.isEmpty)
    }

    func testRevokeFailureSurfacesErrorAndKeepsList() async {
        service.sessionsResult = .success([FronteggSession(id: "other", isCurrent: false)])
        let viewModel = makeViewModel()
        await viewModel.load()
        service.actionError = FronteggSecurityCenterError.requestFailed(statusCode: 500)

        await viewModel.revoke(FronteggSession(id: "other", isCurrent: false))

        XCTAssertEqual(viewModel.errorMessage, FronteggSecurityCenterError.requestFailed(statusCode: 500).localizedDescription)
        XCTAssertEqual(viewModel.sessions.map(\.id), ["other"])
        XCTAssertTrue(viewModel.pendingIds.isEmpty)
    }

    func testRevokeOtherSessionsCallsServiceAndReloads() async {
        let viewModel = makeViewModel()

        await viewModel.revokeOtherSessions()

        XCTAssertEqual(service.revokeOtherSessionsCalls, 1)
        XCTAssertEqual(service.listSessionsCalls, 1)
        XCTAssertFalse(viewModel.isRevokingOtherSessions)
    }

    func testDeletePasskeyCallsServiceAndReloads() async {
        service.passkeysResult = .success([FronteggPasskey(id: "pk1", deviceType: .platform)])
        let viewModel = makeViewModel()
        await viewModel.load()
        service.passkeysResult = .success([])

        await viewModel.delete(FronteggPasskey(id: "pk1", deviceType: .platform))

        XCTAssertEqual(service.deletedPasskeyIds, ["pk1"])
        XCTAssertTrue(viewModel.passkeys.isEmpty)
        XCTAssertEqual(service.listPasskeysCalls, 2)
    }

    func testDeletePasskeyFailureSurfacesError() async {
        service.actionError = FronteggSecurityCenterError.requestFailed(statusCode: 404)
        let viewModel = makeViewModel()

        await viewModel.delete(FronteggPasskey(id: "pk1", deviceType: .platform))

        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testAddPasskeyRegistersThenReloadsPasskeys() async {
        let viewModel = makeViewModel()
        service.passkeysResult = .success([FronteggPasskey(id: "new", deviceType: .platform)])

        await viewModel.addPasskey()

        XCTAssertEqual(service.registerPasskeyCalls, 1)
        XCTAssertEqual(viewModel.passkeys.map(\.id), ["new"])
        XCTAssertFalse(viewModel.isAddingPasskey)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testAddPasskeyCancelledByUserDoesNotSurfaceError() async {
        service.actionError = FronteggError.authError(.operationCanceled)
        let viewModel = makeViewModel()

        await viewModel.addPasskey()

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(service.listPasskeysCalls, 0)
    }

    func testAddPasskeyFailureSurfacesError() async {
        service.actionError = FronteggError.authError(.invalidPasskeysRequest)
        let viewModel = makeViewModel()

        await viewModel.addPasskey()

        XCTAssertEqual(viewModel.errorMessage, FronteggError.authError(.invalidPasskeysRequest).localizedDescription)
    }

    func testStepUpPassesMaxAgeAndUpdatesStatus() async {
        let viewModel = makeViewModel(stepUpMaxAge: 300)
        XCTAssertFalse(viewModel.isSteppedUp)

        await viewModel.stepUp()

        XCTAssertEqual(service.stepUpMaxAges, [300])
        XCTAssertTrue(viewModel.isSteppedUp)
        XCTAssertFalse(viewModel.isSteppingUp)
    }

    func testStepUpFailureSurfacesError() async {
        service.actionError = FronteggError.authError(.failedToMFA)
        let viewModel = makeViewModel()

        await viewModel.stepUp()

        XCTAssertFalse(viewModel.isSteppedUp)
        XCTAssertEqual(viewModel.errorMessage, FronteggError.authError(.failedToMFA).localizedDescription)
    }

    func testUserPublisherDrivesMfaStatusAndActiveTenantName() throws {
        let viewModel = makeViewModel()
        XCTAssertFalse(viewModel.mfaEnrolled)
        XCTAssertNil(viewModel.activeTenantName)

        userSubject.send(try makeUser(mfaEnrolled: true, tenantName: "Globex"))

        XCTAssertTrue(viewModel.mfaEnrolled)
        XCTAssertEqual(viewModel.activeTenantName, "Globex")
    }

    func testActiveTenantChangeRefreshesStepUpStatus() throws {
        let viewModel = makeViewModel()
        XCTAssertFalse(viewModel.isSteppedUp)

        service.steppedUp = true
        userSubject.send(try makeUser(mfaEnrolled: false))

        XCTAssertTrue(viewModel.isSteppedUp)
    }
}
