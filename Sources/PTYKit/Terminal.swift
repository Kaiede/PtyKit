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

fileprivate let logger = Logger(label: "ptykit.terminal")

public enum TerminalNewline {
    case `default`
    case ssh
}

public typealias TerminalListener = (String) -> Void

public final class PseudoTerminal {
    public final class Channel {
        public let fileHandle: FileHandle
        public var fileDescriptor: Int32 { fileHandle.fileDescriptor }

        private var token: Int?
        private weak var terminal: PseudoTerminal?

        fileprivate init(handle: FileHandle, terminal: PseudoTerminal, token: Int) {
            self.fileHandle = handle
            self.terminal = terminal
            self.token = token
        }

        public func disconnect() throws {
            guard let token = token else { return }

            try self.terminal?.disconnect(token: token)
            self.token = nil
        }
    }

    // PTY Handles
    // - Host is for reading/writing
    // - Child is to attach to child processes
    let hostHandle: FileHandle
    let childHandle: FileHandle

    private let identifier: String
    private let newline: TerminalNewline
    private let attachLock: NSRecursiveLock
    private var attachToken: Int?
    private var detachHandlers: [() -> Void]

    private var currentExpects: [String:TerminalListener]
    private var currentListener: TerminalListener?

    public var isAttached: Bool {
        return attachToken != nil
    }

    public init(identifier: String = "Terminal", newline: TerminalNewline = .default) throws {
        self.identifier = identifier
        self.newline = newline
        attachLock = NSRecursiveLock()
        detachHandlers = []
        currentExpects = [:]
        attachToken = nil
        hostHandle = try PseudoTerminal.openPTY(identifier: identifier)
        childHandle = try PseudoTerminal.getChildPTY(parent: hostHandle, identifier: identifier)

        hostHandle.readabilityHandler = { [weak self] handle in
            self?.readReceivedData(fileHandle: handle)
        }
    }

    deinit {
        do {
            hostHandle.readabilityHandler = nil
            try childHandle.close()
            try hostHandle.close()
        } catch let error {
            logger.warning("Error encountered closing PTY: \(error.localizedDescription)")
        }
    }

    public func connect() throws -> Channel {
        attachLock.lock()
        defer { attachLock.unlock() }

        guard !isAttached else {
            throw PTYError.alreadyAttached
        }

        let token = Int.random(in: Int.min...Int.max)
        attachToken = token
        return Channel(handle: self.childHandle, terminal: self, token: token)
    }

    func disconnect(token: Int) throws {
        attachLock.lock()
        defer { attachLock.unlock() }

        guard isAttached && attachToken == token else {
            throw PTYError.notAttached
        }

        attachToken = nil
        logger.debug("Calling process detach handlers (\(identifier))")
        for handler in detachHandlers {
            handler()
        }
        detachHandlers = []
        logger.debug("Process detached (\(identifier))")
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

    private func addHandler(_ closure: @escaping () -> Void) -> Bool {
        attachLock.lock()
        defer { attachLock.unlock() }

        if !isAttached {
            return false
        }

        detachHandlers.append(closure)
        return true
    }

    private static func openPTY(identifier: String) throws -> FileHandle {
        let hostDescriptor = CPTYKit_openpty()
        guard -1 != hostDescriptor else {
            throw PTYError.handleCreationFailed
        }

        let ptsPath = String(cString: CPTYKit_ptsname(hostDescriptor))

        logger.info("Host PTY Handle Opened: \(ptsPath)  (\(identifier) - \(hostDescriptor))")

        return FileHandle(fileDescriptor: hostDescriptor, closeOnDealloc: true)
    }

    private static func getChildPTY(parent: FileHandle, identifier: String) throws -> FileHandle {
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

        logger.info("Child PTY Handle Opened: \(ptsPath) (\(identifier) - \(fileHandle.fileDescriptor))")

        return fileHandle
    }
}

// MARK: Window Size

extension PseudoTerminal {
    public func setWindowSize(columns: UInt16, rows: UInt16) throws {
        var size = winsize(ws_row: rows, ws_col: columns, ws_xpixel: 0, ws_ypixel: 0)

        // Parent Terminal
        do {
            let result = ioctl(hostHandle.fileDescriptor, UInt(TIOCSWINSZ), &size)
            if let errorCode = POSIXErrorCode(rawValue: result) {
                throw POSIXError(errorCode)
            }
        }

        // Child Terminal
        do {
            let result = ioctl(childHandle.fileDescriptor, UInt(TIOCSWINSZ), &size)
            if let errorCode = POSIXErrorCode(rawValue: result) {
                throw POSIXError(errorCode)
            }
        }

    }

    public func getWindowSize() throws -> winsize {
        var size = winsize()
        let result = ioctl(childHandle.fileDescriptor, UInt(TIOCGWINSZ), &size)

        if let errorCode = POSIXErrorCode(rawValue: result) {
            throw POSIXError(errorCode)
        }

        return size
    }
}

// MARK: Writing

extension PseudoTerminal {
    public func sendLine(_ content: String) throws {
        switch newline {
        case .default: try send("\(content)\n")
        case .ssh: try send("\(content)\r")
        }
    }

    public func send(_ content: String) throws {
        guard let data = content.data(using: .utf8) else {
            logger.error("Failed to get UTF8 data for content: \(content) (\(identifier))")
            throw PTYError.invalidData
        }

        logger.trace("Sending: \(content) (\(identifier))")
        hostHandle.write(data)
    }

    public func send(_ data: Data) {
        logger.trace("Sending Data: \(data.count) bytes (\(identifier))")
        hostHandle.write(data)
    }

    @available(OSX 10.15.4, *)
    public func send<Data: DataProtocol>(contentsOf data: Data) throws {
        logger.trace("Sending Data: \(data.count) bytes (\(identifier))")
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
                logger.trace("Match found, calling listener (\(self.identifier))")
                handler(content)
            } else {
                logger.trace("No match found for content: \(content) (\(self.identifier))")
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
        logger.debug("Expecting: \(expressions) (\(identifier))")

        // Due to what is believed to be rdar://82985344, we need to clean up
        // the pipe once we've gotten a match. Turns out that the continuation
        // doesn't terminate until the timeout has fired. Unfortunate.
        let pipeId = UUID()
        defer { cancelPipe(id: pipeId) }

        for await content in pipeEvents(timeout: timeout, id: pipeId) {
            logger.debug("Content Read: \(content) (\(identifier))")
            if let foundMatch = self.findMatches(content: content, expressions: expressions) {
                logger.debug("Match Found: \(content) (\(identifier))")
                return .match(foundMatch)
            }
            logger.trace("Content Has No Matches (\(identifier))")
        }

        // If we existed the loop, then we timed out without a match.
        logger.debug("No Matches Found, Timed Out (\(identifier))")
        return .noMatch
    }

    private func cancelPipe(id: UUID) {
        let continuationId = id.uuidString
        if currentExpects[continuationId] != nil {
            logger.trace("Removing Expectation \(continuationId) (\(identifier))")
            currentExpects.removeValue(forKey: continuationId)
        }
    }

    private func pipeEvents(timeout: TimeInterval = .infinity, id: UUID) -> AsyncStream<String> {
        AsyncStream { continuation in
            let continuationId = id.uuidString

            continuation.onTermination = { @Sendable _ in
                self.cancelPipe(id: id)
            }

            logger.trace("Adding Expectation \(continuationId) (\(identifier))")
            self.currentExpects[continuationId] = { content in
                continuation.yield(content)
            }

            if timeout != .infinity {
                logger.debug("Timeout for Expectation is \(timeout) s (\(identifier))")
                let deadline = Date().advanced(by: timeout)
                let wallDeadline = DispatchWallTime(date: deadline)
                DispatchQueue.global().asyncAfter(wallDeadline: wallDeadline) {
                    if self.currentExpects[continuationId] != nil {
                        logger.debug("Timeout Reached for \(continuationId)")
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
        logger.trace("Data Received on file descriptor (\(identifier) - \(fileHandle.fileDescriptor))")
        let data = fileHandle.availableData

        // Handle EOF State
        guard data.count > 0 else {
            logger.debug("EOF received on file descriptor (\(identifier) - \(fileHandle.fileDescriptor))")
            return
        }

        guard let content = String(data: data, encoding: .utf8) else {
            logger.error("Unable to read string data from terminal (\(identifier))")
            return
        }

        logger.trace("Processing \(currentExpects.count) Expects (\(identifier))")
        for handler in currentExpects.values {
            handler(content)
        }

        if let handler = currentListener {
            logger.trace("Processing Listener (\(identifier))")
            handler(content)
        }
    }
}

