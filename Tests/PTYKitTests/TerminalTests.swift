import XCTest
@testable import PTYKit

final class TerminalTests: XCTestCase {
    func testBasicSend() {
        do {
            let terminal = try PseudoTerminal()

            try terminal.sendLine("Some Basic String")
        } catch let error {
            XCTFail("\(error.localizedDescription)")
        }
    }

    func testBasicReceive() {
        let asyncExpect = expectation(description: "Task Completed")
        Task {
            do {
                let terminal = try PseudoTerminal()

                let match = await terminal.expect("Basic Expectation", timeout: 0.1)
                XCTAssertEqual(match, .noMatch)
            } catch let error {
                XCTFail("\(error.localizedDescription)")
            }

            asyncExpect.fulfill()
        }

        waitForExpectations(timeout: 0.2)
    }

    func testOpenManyTerminalsInSerial() {
        let asyncExpect = expectation(description: "Task Completed")
        Task {
            do {
                for _ in 0...128 {
                    let terminal = try PseudoTerminal()
                    
                    let match = await terminal.expect("Basic Expectation", timeout: 0.01)
                    XCTAssertEqual(match, .noMatch)
                }
            } catch let error {
                XCTFail("\(error.localizedDescription)")
            }

            asyncExpect.fulfill()
        }

        waitForExpectations(timeout: 5)
    }

    func testOpenManyTerminalsInParallel() {
        do {
            let array = Array(0...128)
            let terminals = try array.map({ _ in
                return try PseudoTerminal()
            })
        } catch let error {
            XCTFail("\(error.localizedDescription)")
        }
    }

    func testBasicShell() {
        let asyncExpect = expectation(description: "Task Completed")
        Task {
            do {
                let terminal = try PseudoTerminal()
                let shellUrl = URL(fileURLWithPath: "/bin/sh")
                let process = try Process(shellUrl, arguments: [], terminal: terminal)

                XCTAssertTrue(terminal.isAttached)

                try process.run()

                try terminal.sendLine("whoami")
                let username = NSUserName()

                let match1 = await terminal.expect(username, timeout: 0.5)
                XCTAssertNotEqual(match1, .noMatch)

                process.terminate()
            } catch let error {
                XCTFail("\(error.localizedDescription)")
            }
            
            asyncExpect.fulfill()
        }

        waitForExpectations(timeout: 5)
    }
}
