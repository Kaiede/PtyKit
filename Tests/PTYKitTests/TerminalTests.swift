import XCTest
@testable import PTYKit

final class TerminalTests: XCTestCase {
    func testBasicSend() async {
        do {
            let terminal = try PseudoTerminal()

            try await terminal.sendLine("Some Basic String")
        } catch let error {
            XCTFail("\(error.localizedDescription)")
        }
    }

    func testDefaultNewline() async {
        do {
            let terminal = try PseudoTerminal()
            let shellUrl = URL(fileURLWithPath: "/bin/cat")
            let process = try await Process(shellUrl, arguments: [], terminal: terminal)

            try process.run()

            let expectation = expectation(description: "Should get results")
            expectation.expectedFulfillmentCount = 2 // both send and receive should show up
            try await terminal.sendLine("Hello World")
            await terminal.listen(for: ".*", handler: { line in
                // The \n becomes a single \r\n via 'cat'
                XCTAssertEqual(line, "Hello World\r\n")
                expectation.fulfill()
            })

            await fulfillment(of: [expectation], timeout: 0.1)
        } catch let error {
            XCTFail("\(error.localizedDescription)")
        }
    }

    func testSshNewline() async {
        do {
            let terminal = try PseudoTerminal(newline: .ssh)
            let shellUrl = URL(fileURLWithPath: "/bin/cat")
            let process = try await Process(shellUrl, arguments: [], terminal: terminal)

            try process.run()

            let expectation = expectation(description: "Should get results")
            expectation.expectedFulfillmentCount = 2 // both send and receive should show up
            try await terminal.sendLine("Hello World")
            await terminal.listen(for: ".*", handler: { line in
                // The \r should still wind up being an \r\n
                XCTAssertEqual(line, "Hello World\r\n")
                expectation.fulfill()
            })

            await fulfillment(of: [expectation], timeout: 0.1)
        } catch let error {
            XCTFail("\(error.localizedDescription)")
        }
    }

    func testBasicReceive() async {
        do {
            let terminal = try PseudoTerminal()

            let match = await terminal.expect("Basic Expectation", timeout: 0.1)
            XCTAssertEqual(match, .noMatch)
        } catch let error {
            XCTFail("\(error.localizedDescription)")
        }
    }

    func testOpenManyTerminalsInSerial() async {
        do {
            for _ in 0...128 {
                let terminal = try PseudoTerminal()
                
                let match = await terminal.expect("Basic Expectation", timeout: 0.01)
                XCTAssertEqual(match, .noMatch)
            }
        } catch let error {
            XCTFail("\(error.localizedDescription)")
        }
    }

    func testOpenManyTerminalsInParallel() {
        do {
            let array = Array(0...128)
            let terminals = try array.map({ _ in
                return try PseudoTerminal()
            })
            XCTAssert(terminals.count == 129)
        } catch let error {
            XCTFail("\(error.localizedDescription)")
        }
    }

    func testBasicShell() async {
        do {
            let terminal = try PseudoTerminal()
            let shellUrl = URL(fileURLWithPath: "/bin/sh")
            let process = try await Process(shellUrl, arguments: [], terminal: terminal)

            let isAttached = await terminal.isAttached
            XCTAssertTrue(isAttached)

            try process.run()

            try await terminal.sendLine("whoami")
            let username = NSUserName()

            let match1 = await terminal.expect(username, timeout: 0.5)
            XCTAssertNotEqual(match1, .noMatch)

            process.terminate()
        } catch let error {
            XCTFail("\(error.localizedDescription)")
        }
    }

    func testWindowSize() async throws {
        let terminal = try PseudoTerminal()

        // Why is this 0x0 by default on Mac?
        let size = try await terminal.getWindowSize()
        XCTAssertEqual(size.ws_col, 0)
        XCTAssertEqual(size.ws_row, 0)

        // Set some value and test that it fetches back
        try await terminal.setWindowSize(columns: 80, rows: 24)
        let size2 = try await terminal.getWindowSize()
        XCTAssertEqual(size2.ws_col, 80)
        XCTAssertEqual(size2.ws_row, 24)
    }

    func testError() throws {
        let example = "Failed to get an error: \(PTYError.alreadyAttached)"
        XCTAssertEqual(example, "Failed to get an error: \(PTYError.alreadyAttached.description)")
        XCTAssertEqual(example, "Failed to get an error: \(PTYError.alreadyAttached.localizedDescription)")
    }
}
