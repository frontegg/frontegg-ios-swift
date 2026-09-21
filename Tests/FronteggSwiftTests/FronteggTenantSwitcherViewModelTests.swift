import XCTest
import Combine
@testable import FronteggSwift

@MainActor
final class FronteggTenantSwitcherViewModelTests: XCTestCase {

    @MainActor
    private final class MockSwitcher: FronteggTenantSwitching {
        var requestedTenantIds: [String] = []
        var result: Result<User, Error>
        var onSwitch: (() -> Void)?
        var suspends = false
        private var gate: CheckedContinuation<Void, Never>?

        init(result: Result<User, Error>) {
            self.result = result
        }

        func switchTenant(tenantId: String) async throws -> User {
            requestedTenantIds.append(tenantId)
            onSwitch?()
            if suspends {
                await withCheckedContinuation { gate = $0 }
            }
            return try result.get()
        }

        var isSuspended: Bool { gate != nil }

        func resume() {
            gate?.resume()
            gate = nil
        }
    }

    private func makeUser(activeTenantId: String) throws -> User {
        let tenants = [
            TestDataFactory.makeTenant(id: "t1", name: "Acme", tenantId: "t1"),
            TestDataFactory.makeTenant(id: "t2", name: "Globex", tenantId: "t2"),
            TestDataFactory.makeTenant(id: "t3", name: "Initech", tenantId: "t3")
        ]
        let active = tenants.first { ($0["tenantId"] as? String) == activeTenantId }!
        let data = try TestDataFactory.jsonData(from: TestDataFactory.makeUser(
            tenantId: activeTenantId,
            tenantIds: ["t1", "t2", "t3"],
            tenants: tenants,
            activeTenant: active
        ))
        return try JSONDecoder().decode(User.self, from: data)
    }

    private func makeViewModel(
        user: User?,
        switcher: MockSwitcher
    ) -> (FronteggTenantSwitcherViewModel, CurrentValueSubject<User?, Never>) {
        let subject = CurrentValueSubject<User?, Never>(user)
        let viewModel = FronteggTenantSwitcherViewModel(
            switcher: switcher,
            userPublisher: subject.eraseToAnyPublisher()
        )
        return (viewModel, subject)
    }

    func testTenantsAndActiveTenantComeFromUser() throws {
        let user = try makeUser(activeTenantId: "t2")
        let (viewModel, _) = makeViewModel(user: user, switcher: MockSwitcher(result: .success(user)))

        XCTAssertEqual(viewModel.tenants.map(\.tenantId), ["t1", "t2", "t3"])
        XCTAssertEqual(viewModel.activeTenantId, "t2")
        XCTAssertTrue(viewModel.isActive(user.tenants[1]))
        XCTAssertFalse(viewModel.isActive(user.tenants[0]))
    }

    func testNoUserMeansNoTenants() {
        let (viewModel, _) = makeViewModel(
            user: nil,
            switcher: MockSwitcher(result: .failure(FronteggError.authError(.notAuthenticated)))
        )

        XCTAssertTrue(viewModel.tenants.isEmpty)
        XCTAssertNil(viewModel.activeTenantId)
    }

    func testSelectingAnotherTenantSwitchesAndUpdatesActiveTenant() async throws {
        let user = try makeUser(activeTenantId: "t1")
        let switched = try makeUser(activeTenantId: "t3")
        let switcher = MockSwitcher(result: .success(switched))
        let (viewModel, _) = makeViewModel(user: user, switcher: switcher)
        var inFlightTenantId: String?
        switcher.onSwitch = { inFlightTenantId = viewModel.switchingTenantId }

        let result = await viewModel.select(user.tenants[2])

        XCTAssertEqual(switcher.requestedTenantIds, ["t3"])
        XCTAssertEqual(inFlightTenantId, "t3")
        XCTAssertNil(viewModel.switchingTenantId)
        XCTAssertEqual(viewModel.activeTenantId, "t3")
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(try result?.get().activeTenant.tenantId, "t3")
    }

    func testSelectingActiveTenantIsNoOp() async throws {
        let user = try makeUser(activeTenantId: "t1")
        let switcher = MockSwitcher(result: .success(user))
        let (viewModel, _) = makeViewModel(user: user, switcher: switcher)

        let result = await viewModel.select(user.tenants[0])

        XCTAssertNil(result)
        XCTAssertTrue(switcher.requestedTenantIds.isEmpty)
    }

    func testSwitchFailureSurfacesErrorAndKeepsActiveTenant() async throws {
        let user = try makeUser(activeTenantId: "t1")
        let switcher = MockSwitcher(result: .failure(FronteggError.authError(.failedToSwitchTenant)))
        let (viewModel, _) = makeViewModel(user: user, switcher: switcher)

        let result = await viewModel.select(user.tenants[1])

        XCTAssertEqual(viewModel.errorMessage, FronteggError.authError(.failedToSwitchTenant).localizedDescription)
        XCTAssertEqual(viewModel.activeTenantId, "t1")
        XCTAssertNil(viewModel.switchingTenantId)
        if case .success = result { XCTFail("expected failure") }
    }

    func testSelectWhileSwitchingIsIgnored() async throws {
        let user = try makeUser(activeTenantId: "t1")
        let switcher = MockSwitcher(result: .success(try makeUser(activeTenantId: "t2")))
        switcher.suspends = true
        let (viewModel, _) = makeViewModel(user: user, switcher: switcher)

        let first = Task { await viewModel.select(user.tenants[1]) }
        while !switcher.isSuspended { await Task.yield() }

        XCTAssertTrue(viewModel.isSwitching)
        let second = await viewModel.select(user.tenants[2])
        XCTAssertNil(second)

        switcher.resume()
        _ = await first.value

        XCTAssertEqual(switcher.requestedTenantIds, ["t2"])
        XCTAssertEqual(viewModel.activeTenantId, "t2")
        XCTAssertFalse(viewModel.isSwitching)
    }

    func testUserPublisherUpdatesTenants() throws {
        let (viewModel, subject) = makeViewModel(
            user: nil,
            switcher: MockSwitcher(result: .failure(FronteggError.authError(.unknown)))
        )

        subject.send(try makeUser(activeTenantId: "t2"))

        XCTAssertEqual(viewModel.tenants.count, 3)
        XCTAssertEqual(viewModel.activeTenantId, "t2")
    }

    func testSearchFiltersTenantsByNameCaseInsensitively() throws {
        let user = try makeUser(activeTenantId: "t1")
        let (viewModel, _) = makeViewModel(user: user, switcher: MockSwitcher(result: .success(user)))

        XCTAssertEqual(viewModel.filteredTenants.count, 3)
        viewModel.searchText = "glo"
        XCTAssertEqual(viewModel.filteredTenants.map(\.tenantId), ["t2"])
        viewModel.searchText = "  "
        XCTAssertEqual(viewModel.filteredTenants.count, 3)
    }
}
