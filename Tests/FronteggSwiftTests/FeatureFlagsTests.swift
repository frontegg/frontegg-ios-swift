//
//  FeatureFlagsTests.swift
//  FronteggSwiftTests
//

import XCTest
@testable import FronteggSwift

// MARK: - Mock Api for Feature Flags Testing

class MockFeatureFlagsApi: Api {
    var getFeatureFlagsResult: Result<String, Error> = .success("{}")
    var getFeatureFlagsCallCount = 0
    
    init() {
        // Initialize with dummy values - we won't use the network
        super.init(baseUrl: "https://test.example.com", clientId: "test-client", applicationId: nil)
    }
    
    override func getFeatureFlags() async throws -> String {
        getFeatureFlagsCallCount += 1
        switch getFeatureFlagsResult {
        case .success(let json):
            return json
        case .failure(let error):
            throw error
        }
    }
}

final class FeatureFlagsTests: XCTestCase {
    
    var mockApi: MockFeatureFlagsApi!
    var testStorage: UserDefaults!
    var featureFlags: FeatureFlags!
    let testStorageKey = "featureflags:test-client"
    
    override func setUp() {
        super.setUp()
        mockApi = MockFeatureFlagsApi()
        testStorage = UserDefaults.standard
        // Clean up any existing test data
        testStorage.removeObject(forKey: testStorageKey)
    }
    
    override func tearDown() {
        testStorage.removeObject(forKey: testStorageKey)
        featureFlags = nil
        mockApi = nil
        super.tearDown()
    }
    
    // MARK: - Helper
    
    func createFeatureFlags() -> FeatureFlags {
        let config = FeatureFlags.Config(
            clientId: "test-client",
            api: mockApi,
            storage: testStorage
        )
        return FeatureFlags(config)
    }
    
    // MARK: - Constants Tests
    
    func test_mobileEnableLoggingKey_hasCorrectValue() {
        XCTAssertEqual(FeatureFlags.mobileEnableLoggingKey, "mobile-enable-logging")
    }
    
    // MARK: - Config Tests
    
    func test_config_initializesCorrectly() {
        let config = FeatureFlags.Config(
            clientId: "my-client",
            api: mockApi,
            storage: testStorage
        )
        
        XCTAssertEqual(config.clientId, "my-client")
        XCTAssertNotNil(config.api)
        XCTAssertNotNil(config.storage)
    }
    
    func test_config_usesDefaultStorage() {
        let config = FeatureFlags.Config(
            clientId: "my-client",
            api: mockApi
        )
        
        XCTAssertNotNil(config.storage)
    }
    
    // MARK: - Initial State Tests
    
    func test_initialState_notReady_whenNoFlags() {
        featureFlags = createFeatureFlags()
        XCTAssertFalse(featureFlags.ready)
    }
    
    // MARK: - hasFlag Tests
    
    func test_hasFlag_returnsFalse_whenFlagNotPresent() async {
        mockApi.getFeatureFlagsResult = .success("{\"other-flag\": \"on\"}")
        featureFlags = createFeatureFlags()
        await featureFlags.start()
        
        XCTAssertFalse(featureFlags.hasFlag("non-existent-flag"))
    }
    
    func test_hasFlag_returnsTrue_whenFlagPresent() async {
        mockApi.getFeatureFlagsResult = .success("{\"my-feature\": \"on\"}")
        featureFlags = createFeatureFlags()
        await featureFlags.start()
        
        XCTAssertTrue(featureFlags.hasFlag("my-feature"))
    }
    
    // MARK: - isOn Tests
    
    func test_isOn_returnsFalse_whenFlagNotPresent() async {
        mockApi.getFeatureFlagsResult = .success("{}")
        featureFlags = createFeatureFlags()
        await featureFlags.start()
        
        XCTAssertFalse(featureFlags.isOn("missing-flag"))
    }
    
    func test_isOn_returnsTrue_whenFlagIsOn() async {
        mockApi.getFeatureFlagsResult = .success("{\"enabled-feature\": \"on\"}")
        featureFlags = createFeatureFlags()
        await featureFlags.start()
        
        XCTAssertTrue(featureFlags.isOn("enabled-feature"))
    }
    
    func test_isOn_returnsFalse_whenFlagIsOff() async {
        mockApi.getFeatureFlagsResult = .success("{\"disabled-feature\": \"off\"}")
        featureFlags = createFeatureFlags()
        await featureFlags.start()
        
        XCTAssertFalse(featureFlags.isOn("disabled-feature"))
    }
    
    func test_isOn_handlesTrue_asOn() async {
        mockApi.getFeatureFlagsResult = .success("{\"true-feature\": \"true\"}")
        featureFlags = createFeatureFlags()
        await featureFlags.start()
        
        XCTAssertTrue(featureFlags.isOn("true-feature"))
    }
    
    func test_isOn_handlesFalse_asOff() async {
        mockApi.getFeatureFlagsResult = .success("{\"false-feature\": \"false\"}")
        featureFlags = createFeatureFlags()
        await featureFlags.start()
        
        XCTAssertFalse(featureFlags.isOn("false-feature"))
    }
    
    func test_isOn_handlesWhitespaceAndCase() async {
        mockApi.getFeatureFlagsResult = .success("{\"whitespace-flag\": \"  ON  \", \"upper-flag\": \"TRUE\"}")
        featureFlags = createFeatureFlags()
        await featureFlags.start()
        
        XCTAssertTrue(featureFlags.isOn("whitespace-flag"))
        XCTAssertTrue(featureFlags.isOn("upper-flag"))
    }
    
    // MARK: - ready Property Tests
    
    func test_ready_becomesTrue_afterSuccessfulFetch() async {
        mockApi.getFeatureFlagsResult = .success("{\"flag\": \"on\"}")
        featureFlags = createFeatureFlags()
        
        XCTAssertFalse(featureFlags.ready)
        
        await featureFlags.start()
        
        XCTAssertTrue(featureFlags.ready)
    }
    
    // MARK: - fetchFeatureFlags Tests
    
    func test_fetchFeatureFlags_returnsTrue_onSuccess() async {
        mockApi.getFeatureFlagsResult = .success("{\"flag\": \"on\"}")
        featureFlags = createFeatureFlags()
        await featureFlags.start()
        
        let result = await featureFlags.fetchFeatureFlags()
        
        XCTAssertTrue(result)
    }
    
    // MARK: - Multiple Flags Tests
    
    func test_multipleFlags_parsedCorrectly() async {
        let json = """
        {
            "flag-a": "on",
            "flag-b": "off",
            "flag-c": "true",
            "flag-d": "false"
        }
        """
        mockApi.getFeatureFlagsResult = .success(json)
        featureFlags = createFeatureFlags()
        await featureFlags.start()
        
        XCTAssertTrue(featureFlags.hasFlag("flag-a"))
        XCTAssertTrue(featureFlags.hasFlag("flag-b"))
        XCTAssertTrue(featureFlags.hasFlag("flag-c"))
        XCTAssertTrue(featureFlags.hasFlag("flag-d"))
        
        XCTAssertTrue(featureFlags.isOn("flag-a"))
        XCTAssertFalse(featureFlags.isOn("flag-b"))
        XCTAssertTrue(featureFlags.isOn("flag-c"))
        XCTAssertFalse(featureFlags.isOn("flag-d"))
    }
    
    // MARK: - Invalid Value Tests
    
    func test_invalidValues_areIgnored() async {
        let json = """
        {
            "valid-flag": "on",
            "invalid-flag": "maybe",
            "another-invalid": "yes"
        }
        """
        mockApi.getFeatureFlagsResult = .success(json)
        featureFlags = createFeatureFlags()
        await featureFlags.start()
        
        XCTAssertTrue(featureFlags.hasFlag("valid-flag"))
        XCTAssertFalse(featureFlags.hasFlag("invalid-flag"))
        XCTAssertFalse(featureFlags.hasFlag("another-invalid"))
    }
    
    // MARK: - Empty Response Tests
    
    func test_emptyJson_resultsInNoFlags() async {
        mockApi.getFeatureFlagsResult = .success("{}")
        featureFlags = createFeatureFlags()
        await featureFlags.start()
        
        XCTAssertFalse(featureFlags.hasFlag("any-flag"))
        XCTAssertFalse(featureFlags.isOn("any-flag"))
    }
    
    // MARK: - Cache Tests
    
    func test_flagsAreCached_toStorage() async {
        let json = "{\"cached-flag\": \"on\"}"
        mockApi.getFeatureFlagsResult = .success(json)
        featureFlags = createFeatureFlags()
        await featureFlags.start()
        
        // Check that data was saved to storage
        let cachedData = testStorage.data(forKey: testStorageKey)
        XCTAssertNotNil(cachedData)
        
        if let data = cachedData,
           let cached = try? JSONDecoder().decode([String: Bool].self, from: data) {
            XCTAssertEqual(cached["cached-flag"], true)
        } else {
            XCTFail("Failed to decode cached flags")
        }
    }
    
    func test_cachedFlags_areLoadedOnStart() async {
        // Pre-populate cache
        let cachedFlags = ["pre-cached-flag": true]
        if let data = try? JSONEncoder().encode(cachedFlags) {
            testStorage.set(data, forKey: testStorageKey)
        }
        
        // Create flags with an API that returns valid data
        mockApi.getFeatureFlagsResult = .success("{\"pre-cached-flag\": \"on\"}")
        featureFlags = createFeatureFlags()
        await featureFlags.start()
        
        // After start, flags should be available
        XCTAssertTrue(featureFlags.ready)
        XCTAssertTrue(featureFlags.isOn("pre-cached-flag"))
    }
}
