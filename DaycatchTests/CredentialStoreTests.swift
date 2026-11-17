import XCTest

final class CredentialStoreTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appending(path: "daycatch-tests-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    func testRoundTripPerProvider() {
        let store = CredentialStore(directory: directory)
        XCTAssertEqual(store.apiKey(for: .anthropic), "")
        XCTAssertTrue(store.setAPIKey("  sk-ant-123\n", for: .anthropic))
        XCTAssertTrue(store.setAPIKey("sk-ds", for: .deepseek))
        XCTAssertEqual(store.apiKey(for: .anthropic), "sk-ant-123")
        XCTAssertEqual(store.apiKey(for: .deepseek), "sk-ds")
        XCTAssertEqual(CredentialStore(directory: directory).apiKey(for: .anthropic), "sk-ant-123")
    }

    func testOverwriteWithShorterKeyAndClear() {
        let store = CredentialStore(directory: directory)
        store.setAPIKey(String(repeating: "x", count: 200), for: .openai)
        store.setAPIKey("short", for: .openai)
        XCTAssertEqual(store.apiKey(for: .openai), "short")
        store.setAPIKey("", for: .openai)
        XCTAssertEqual(store.apiKey(for: .openai), "")
    }

    func testFileIsOwnerOnly() throws {
        let store = CredentialStore(directory: directory)
        store.setAPIKey("sk", for: .anthropic)
        let fileMode = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)[.posixPermissions] as? Int
        let dirMode = try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? Int
        XCTAssertEqual(fileMode, 0o600)
        XCTAssertEqual(dirMode, 0o700)
    }

    func testCorruptFileReadsAsEmpty() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = CredentialStore(directory: directory)
        try Data("not json".utf8).write(to: store.fileURL)
        XCTAssertEqual(store.apiKey(for: .anthropic), "")
        XCTAssertTrue(store.setAPIKey("sk", for: .anthropic))
        XCTAssertEqual(store.apiKey(for: .anthropic), "sk")
    }
}
