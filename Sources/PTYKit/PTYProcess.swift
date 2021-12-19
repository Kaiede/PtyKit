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

import CoreFoundation
import Foundation
import Logging

enum PTYProcessError: Error {
    case InvalidData
}

public class PTYProcess {
    enum ExpectAction {
        case keepListening
        case exit
    }
    
    public enum ExpectResult: Equatable {
        case noMatch
        case match(String)
    }
    
    let logger: Logger
    let process: Process
    var observer: NSObjectProtocol?
    
    // PTY File Handles
    let hostHandle: FileHandle
    let childHandle: FileHandle
    
    let outputPipe: Pipe
    
    var currentExpect: ((String) -> ExpectAction)?
    var currentRunLoop: CFRunLoop?

    public var isRunning: Bool {
        self.process.isRunning
    }

    public init(_ launchExecutable: URL, arguments: [String]) throws {
        logger = Logger(label: "PTYProcess:\(launchExecutable.lastPathComponent)")
        process = Process()
        process.executableURL = launchExecutable
        process.arguments = arguments
        
        // Configure Handles
        outputPipe = Pipe()
        hostHandle = try FileHandle.openPTY()
        childHandle = try hostHandle.getChildPTY()
    }
    
    
    public func run() throws {
        process.standardInput = childHandle
        process.standardError = outputPipe
        process.standardOutput = outputPipe
        
        logger.trace("Launching")
        try process.run()
        
        process.terminationHandler = { _ in
            self.logger.info("Process Terminated: \(self.process.executableURL?.path ?? "<<UNKNOWN>>")")
        }
    }
    
    public func terminate() {
        process.terminate()
    }
    
    public func waitUntilExit() {
        process.waitUntilExit()
    }
    
    public func sendLine(_ content: String) throws {
        try send("\(content)\n")
    }
    
    public func send(_ content: String) throws {
        guard process.isRunning else {
            return
        }
        
        guard let data = content.data(using: .utf8) else {
            throw PTYProcessError.InvalidData
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

    public func expect(_ expressions: String, timeout: TimeInterval = .infinity) async -> ExpectResult {
        return await expect([expressions], timeout: timeout)
    }

    public func expect(_ expressions: [String], timeout: TimeInterval = .infinity) async -> ExpectResult {
        guard process.isRunning else {
            return .noMatch
        }

        logger.debug("Expecting: \(expressions)")

        for await content in pipeEvents(timeout: timeout) {
            logger.trace("Content Read: \(content)")
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

    public func expect(_ expressions: String, timeout: TimeInterval = .infinity) -> ExpectResult {
        return expect([expressions], timeout: timeout)
    }
    
    public func expect(_ expressions: [String], timeout: TimeInterval = .infinity) -> ExpectResult {
        guard process.isRunning else {
            return .noMatch
        }
        

        // Run the loop until we time out or we found a result
        logger.trace("Starting RunLoop")
        var result: ExpectResult = .noMatch
        startBackgroundReading { content in
            // Find matches and break if we find one, otherwise keep listening
            if let foundMatch = self.findMatches(content: content, expressions: expressions) {
                result = .match(foundMatch)
                return .exit
            }
            
            return .keepListening
        }
        
        let timeoutDate = Date().addingTimeInterval(timeout)
        while result == .noMatch && Date() < timeoutDate && process.isRunning {
            let _ = RunLoop.current.run(mode: .default, before: timeoutDate)
        }

        cleanupBackgroundReading()
        
        currentExpect = nil
        return result
    }

    private func pipeEvents(timeout: TimeInterval = .infinity) -> AsyncStream<String> {
        AsyncStream { continuation in
            continuation.onTermination = { @Sendable _ in
                self.outputPipe.fileHandleForReading.readabilityHandler = nil
            }

            self.outputPipe.fileHandleForReading.readabilityHandler = { fileHandle in
                if let content = self.readReceivedData(fileHandle: fileHandle) {
                    continuation.yield(content)
                }
            }

            let deadline = Date().advanced(by: timeout)
            let wallDeadline = DispatchWallTime(date: deadline)
            DispatchQueue.global().asyncAfter(wallDeadline: wallDeadline) {
                continuation.finish()
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
    
    private func startBackgroundReading(expect: @escaping (String) -> ExpectAction) {
        DispatchQueue.main.async { [self] in
            logger.trace("Background Reading Start")
            self.currentRunLoop = CFRunLoopGetCurrent()
            self.currentExpect = expect
            outputPipe.fileHandleForReading.readabilityHandler = didReceiveData
        }
    }
    
    private func cleanupBackgroundReading() {
        logger.trace("Background Reading Cleanup")
        outputPipe.fileHandleForReading.readabilityHandler = nil
        currentExpect = nil
    }
    
    private func stopBackgroundReading() {
        DispatchQueue.main.async {
            self.logger.trace("Background Reading Stop")
            if let loop = self.currentRunLoop {
                CFRunLoopStop(loop)
            }
        }
    }

    private func readReceivedData(fileHandle: FileHandle) -> String? {
        let data = fileHandle.availableData

        // Handle EOF State
        guard data.count > 0 else {
            return nil
        }

        guard let content = String(data: data, encoding: .utf8) else {
            return nil
        }

        return content
    }
    
    private func didReceiveData(fileHandle: FileHandle) {
        let data = fileHandle.availableData
        
        // Handle EOF State
        guard data.count > 0 else {
            stopBackgroundReading()
            return
        }
        
        guard let content = String(data: data, encoding: .utf8) else {
            stopBackgroundReading()
            return
        }

        logger.trace("Content Read: \(content)")
        let action = self.currentExpect?(content) ?? .exit
        switch action {
        case .exit:
            stopBackgroundReading()
            break
        case .keepListening:
            break
        }
    }
}
