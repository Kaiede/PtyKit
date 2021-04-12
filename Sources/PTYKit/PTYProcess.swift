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

enum PTYProcessError: Error {
    case InvalidData
}

public class PTYProcess {
    enum ExpectAction {
        case keepListening
        case exit
    }
    
    let logger: Logger
    let process: Process
    
    // PTY File Handles
    let hostHandle: FileHandle
    let childHandle: FileHandle
    
    let outputPipe: Pipe
    
    var currentExpect: ((String) -> ExpectAction)?
    
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
        process.launch()
        
        NotificationCenter.default.addObserver(
            forName: .NSFileHandleDataAvailable,
            object: outputPipe.fileHandleForReading,
            queue: nil) { [self] notification in
            
            logger.trace("Received Notification")
            self.didReceiveReadNotification(notification: notification)
        }
        
        process.terminationHandler = { _ in
            self.logger.trace("Terminated")
            CFRunLoopStop(RunLoop.current.getCFRunLoop())
        }
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
        try hostHandle.write(contentsOf: data)
    }
    
    public func expect(_ expressions: String, timeout: TimeInterval = .infinity) -> String? {
        return expect([expressions], timeout: timeout)
    }
    
    public func expect(_ expressions: [String], timeout: TimeInterval = .infinity) -> String? {
        guard process.isRunning else {
            return nil
        }
        
        logger.trace("Expecting: \(expressions)")
        
        var result: String? = nil
        
        currentExpect = { content in
            // Find matches and break if we find one, otherwise keep listening
            result = self.findMatches(content: content, expressions: expressions)
            if result != nil {
                return .exit
            }
            
            return .keepListening
        }
        
        // Run the loop until we time out or we found a result
        RunLoop.current.run(until: Date().addingTimeInterval(timeout))
        
        currentExpect = nil
        return result
    }
    
    private func findMatches(content: String, expressions: [String]) -> String? {
        logger.trace("Content Read: \(content)")
        for expression in expressions {
            let range = content.range(of: expression, options: [.regularExpression, .caseInsensitive])
            if range != nil {
                return expression
            }
        }
        
        return nil
    }
    
    private func didReceiveReadNotification(notification: Notification) {
        logger.trace("Read Notification")
        guard let data = notification.userInfo?[NSFileHandleNotificationDataItem] as? Data else {
            CFRunLoopStop(RunLoop.current.getCFRunLoop())
            return
        }
        
        guard let content = String(data: data, encoding: .utf8) else {
            CFRunLoopStop(RunLoop.current.getCFRunLoop())
            return
        }
        
        logger.trace("Processing: \(content)")
        let action = self.currentExpect?(content) ?? .exit
        switch action {
        case .exit:
            CFRunLoopStop(RunLoop.current.getCFRunLoop())

        case .keepListening:
            outputPipe.fileHandleForReading.readInBackgroundAndNotify()

        }
    }
}
