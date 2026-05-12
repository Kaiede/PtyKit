import Testing
@testable import PTYKit

import Foundation
import Logging

fileprivate var logger = Logger(label: "ptykit.tests")

private let _loggingSetup: Void = {
    LoggingSystem.bootstrap { label in
        var handler = StreamLogHandler.standardOutput(label: label)
        handler.logLevel = .trace
        return handler
    }
}()

@Suite struct TerminalTests {
    init() {
        _ = _loggingSetup
    }

    @Test func testBasicSend() async throws {
        let terminal = try PseudoTerminal()
        try terminal.sendLine("Some Basic String")
    }

    @Test func testDefaultNewline() async throws {
        let terminal = try PseudoTerminal()
        let shellUrl = URL(fileURLWithPath: "/bin/cat")
        let process = try await Process(shellUrl, arguments: [], terminal: terminal)
        try process.run()

        try await confirmation("Should get results", expectedCount: 2) { confirm in
            await terminal.listen(for: ".*", handler: { line in
                // The \n becomes a single \r\n via 'cat'
                #expect(line.starts(with: "Hello World"))
                confirm()
            })
            try terminal.sendLine("Hello World")
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    @Test func testSshNewline() async throws {
        let terminal = try PseudoTerminal(newline: .ssh)
        let shellUrl = URL(fileURLWithPath: "/bin/cat")
        let process = try await Process(shellUrl, arguments: [], terminal: terminal)
        try process.run()

        try await confirmation("Should get results", expectedCount: 2) { confirm in
            await terminal.listen(for: ".*", handler: { line in
                // The \r should still wind up being an \r\n
                #expect(line == "Hello World\r\n")
                confirm()
            })
            try terminal.sendLine("Hello World")
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    @Test func testBasicReceive() async throws {
        let terminal = try PseudoTerminal()
        let match = await terminal.expect("Basic Expectation", timeout: 0.1)
        #expect(match == .noMatch)
    }

    @Test func testOpenManyTerminalsInSerial() async throws {
        for _ in 0...128 {
            let terminal = try PseudoTerminal()
            let match = await terminal.expect("Basic Expectation", timeout: 0.01)
            #expect(match == .noMatch)
        }
    }

    @Test func testOpenManyTerminalsInParallel() throws {
        let array = Array(0...128)
        let terminals = try array.map({ _ in try PseudoTerminal() })
        #expect(terminals.count == 129)
    }

    @Test func testBasicShell() async throws {
        let terminal = try PseudoTerminal()
        let shellUrl = URL(fileURLWithPath: "/bin/sh")
        let process = try await Process(shellUrl, arguments: [], terminal: terminal)

        let isAttached = await terminal.isAttached
        #expect(isAttached)

        try process.run()

        try terminal.sendLine("whoami")
        let username = NSUserName()

        let match1 = await terminal.expect(username, timeout: 1)
        #expect(match1 != .noMatch)

        process.terminate()
    }

    @Test func testWindowSize() async throws {
        let terminal = try PseudoTerminal()

        // Why is this 0x0 by default on Mac?
        let size = try terminal.getWindowSize()
        #expect(size.ws_col == 0)
        #expect(size.ws_row == 0)

        try terminal.setWindowSize(columns: 80, rows: 24)
        let size2 = try terminal.getWindowSize()
        #expect(size2.ws_col == 80)
        #expect(size2.ws_row == 24)
    }

    @Test func testError() {
        let example = "Failed to get an error: \(PTYError.alreadyAttached)"
        #expect(example == "Failed to get an error: \(PTYError.alreadyAttached.description)")
        #expect(example == "Failed to get an error: \(PTYError.alreadyAttached.localizedDescription)")
    }

    @Test func testTimeout() async throws {
        let terminal = try PseudoTerminal()
        let result = await terminal.expect(["Something that never comes"], timeout: 1.0)
        #expect(result == .noMatch)
    }
}
