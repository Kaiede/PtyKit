/*
 PTYKit
 Copyright (c) 2021 Adam Thayer
 Licensed under the MIT license, as follows:
 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:
 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE.)
*/

import Foundation
import Logging

import CPTYKit

private let logger = Logger(label: "ptykit.terminal")

public final class PseudoTerminal {
    public typealias TerminalListener = (String) -> Void

    // PTY Handles
    // - Host is for reading/writing
    // - Child is to attach to child processes
    let hostHandle: FileHandle
    let childHandle: FileHandle

    private let attachLock: NSRecursiveLock
    private var attachToken: Int?
    private var detachHandlers: [() -> Void]

    private var currentExpects: [String:TerminalListener]
    private var currentListener: TerminalListener?

    public var isAttached: Bool {
        return attachToken != nil
    }

    public init() throws {
        attachLock = NSRecursiveLock()
        detachHandlers = []
        currentExpects = [:]
        attachToken = nil
        hostHandle = try PseudoTerminal.openPTY()
        childHandle = try PseudoTerminal.getChildPTY(parent: hostHandle)

        hostHandle.readabilityHandler = { handle in
            self.readReceivedData(fileHandle: handle)
        }
    }

    deinit {
        do {
            try childHandle.close()
            try hostHandle.close()
        } catch let error {
            logger.warning("Error encountered closing PTY: \(error.localizedDescription)")
        }
    }

    func attachProcess() throws -> Int {
        attachLock.lock()
        defer { attachLock.unlock() }

        guard !isAttached else {
            throw PTYError.alreadyAttached
        }

        let token = Int.random(in: Int.min...Int.max)
        attachToken = token
        logger.debug("Process attached")
        return token
    }

    func detachProcess(token: Int) throws {
        attachLock.lock()
        defer { attachLock.unlock() }

        guard isAttached && attachToken == token else {
            throw PTYError.notAttached
        }

        attachToken = nil
        logger.debug("Calling process detach handlers")
        for handler in detachHandlers {
            handler()
        }
        detachHandlers = []
        logger.debug("Process detached")
    }

    public func waitForDetach() async {
        let _: Bool = await withCheckedContinuation({ continuation in
            let didAdd = addHandler {
                continuation.resume(returning: true)
            }

            if !didAdd {
                continuation.resume(returning: false)
            }
        })
    }

    private func isProcessAttached() -> Bool {
        attachLock.lock()
        defer { attachLock.unlock() }

        return isAttached
    }

    private func addHandler(_ closure: @escaping () -> Void) -> Bool {
        attachLock.lock()
        defer { attachLock.unlock() }

        if !isAttached {
            return false
        }

        detachHandlers.append(closure)
        return true
    }

    private static func openPTY() throws -> FileHandle {
        let hostDescriptor = CPTYKit_openpty()
        guard -1 != hostDescriptor else {
            throw PTYError.handleCreationFailed
        }

        let ptsPath = String(cString: CPTYKit_ptsname(hostDescriptor))

        logger.info("Host PTY Handle Opened: \(ptsPath) (\(hostDescriptor))")

        return FileHandle(fileDescriptor: hostDescriptor, closeOnDealloc: true)
    }

    private static func getChildPTY(parent: FileHandle) throws -> FileHandle {
        let hostDescriptor = parent.fileDescriptor
        guard 0 == CPTYKit_grantpt(hostDescriptor) else {
            throw PTYError.grantFailed
        }

        guard 0 == CPTYKit_unlockpt(hostDescriptor) else {
            throw PTYError.unlockFailed
        }

        let ptsPath = String(cString: CPTYKit_ptsname(hostDescriptor))

        guard let fileHandle = FileHandle(forUpdatingAtPath: ptsPath) else {
            throw PTYError.handleCreationFailed
        }

        logger.info("Child PTY Handle Opened: \(ptsPath) (\(fileHandle.fileDescriptor))")

        return fileHandle
    }
}

// MARK: Writing

extension PseudoTerminal {
    public func sendLine(_ content: String) throws {
        try send("\(content)\n")
    }

    public func send(_ content: String) throws {
        guard let data = content.data(using: .utf8) else {
            logger.error("Failed to get UTF8 data for content: \(content)")
            throw PTYError.invalidData
        }

        logger.trace("Sending: \(content)")
        hostHandle.write(data)
    }

    public func send(_ data: Data) {
        logger.trace("Sending Data: \(data.count) bytes")
        hostHandle.write(data)
    }

    @available(OSX 10.15.4, *)
    public func send<Data: DataProtocol>(contentsOf data: Data) throws {
        logger.trace("Sending Data: \(data.count) bytes")
        try hostHandle.write(contentsOf: data)
    }
}

// MARK: Reading

extension PseudoTerminal {
    public enum ExpectResult: Equatable {
        case noMatch
        case match(String)
    }

    public func listen(for expression: String, handler: @escaping TerminalListener) {
        listen(for: [expression], handler: handler)
    }

    public func listen(for expressions: [String], handler: @escaping TerminalListener) {
        self.currentListener = { content in
            if let foundMatch = self.findMatches(content: content, expressions: expressions) {
                logger.trace("Match found for listener, calling")
                handler(foundMatch)
            }
        }
    }

    public func stopListening() {
        self.currentListener = nil
    }

    public func expect(_ expressions: String, timeout: TimeInterval = .infinity) async -> ExpectResult {
        return await expect([expressions], timeout: timeout)
    }

    public func expect(_ expressions: [String], timeout: TimeInterval = .infinity) async -> ExpectResult {
        logger.debug("Expecting: \(expressions)")

        for await content in pipeEvents(timeout: timeout) {
            logger.debug("Content Read: \(content)")
            if let foundMatch = self.findMatches(content: content, expressions: expressions) {
                logger.debug("Match Found: \(content)")
                return .match(foundMatch)
            }
            logger.trace("Content Has No Matches")
        }

        // If we existed the loop, then we timed out without a match.
        logger.debug("No Matches Found, Timed Out")
        return .noMatch
    }

    private func pipeEvents(timeout: TimeInterval = .infinity) -> AsyncStream<String> {
        AsyncStream { continuation in
            let continuationId = UUID().uuidString

            continuation.onTermination = { @Sendable _ in
                self.currentExpects.removeValue(forKey: continuationId)
            }

            self.currentExpects[continuationId] = { content in
                continuation.yield(content)
            }

            if timeout != .infinity {
                logger.debug("Timeout for Expectation is \(timeout) s")
                let deadline = Date().advanced(by: timeout)
                let wallDeadline = DispatchWallTime(date: deadline)
                DispatchQueue.global().asyncAfter(wallDeadline: wallDeadline) {
                    if self.currentExpects[continuationId] != nil {
                        logger.debug("Timeout Reached")
                        continuation.finish()
                    }
                }
            }
        }
    }

    private func findMatches(content: String, expressions: [String]) -> String? {
        for expression in expressions {
            let range = content.range(of: expression, options: [.regularExpression, .caseInsensitive])
            if range != nil {
                return expression
            }
        }

        return nil
    }

    private func readReceivedData(fileHandle: FileHandle) {
        logger.trace("Data Received on file descriptor (\(fileHandle.fileDescriptor))")
        let data = fileHandle.availableData

        // Handle EOF State
        guard data.count > 0 else {
            logger.debug("EOF received on file descriptor (\(fileHandle.fileDescriptor))")
            return
        }

        guard let content = String(data: data, encoding: .utf8) else {
            logger.error("Unable to read string data from terminal")
            return
        }

        if currentExpects.count > 0 {
            logger.trace("Processing \(currentExpects.count) Expects")
        }
        for handler in currentExpects.values {
            handler(content)
        }

        if let handler = currentListener {
            logger.trace("Processing Listener")
            handler(content)
        }
    }
}

