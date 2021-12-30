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
import CPTYKit
import Logging

public enum PTYError: Error {
    case HandleCreationFailed
    case GrantFailed
    case UnlockFailed
}

private let logger: Logger = Logger(label: "ptykit")

extension FileHandle {
    public static func openPTY() throws -> FileHandle {
        let hostDescriptor = CPTYKit_openpty()
        guard -1 != hostDescriptor else {
            throw PTYError.HandleCreationFailed
        }

        let ptsPath = String(cString: CPTYKit_ptsname(hostDescriptor))

        logger.info("Host PTY Opened at: \(ptsPath) (\(hostDescriptor))")

        return FileHandle(fileDescriptor: hostDescriptor, closeOnDealloc: true)
    }

    public func getChildPTY() throws -> FileHandle {
        let hostDescriptor = self.fileDescriptor
        guard 0 == CPTYKit_grantpt(hostDescriptor) else {
            throw PTYError.GrantFailed
        }

        guard 0 == CPTYKit_unlockpt(hostDescriptor) else {
            throw PTYError.UnlockFailed
        }

        let ptsPath = String(cString: CPTYKit_ptsname(hostDescriptor))

        guard let fileHandle = FileHandle(forUpdatingAtPath: ptsPath) else {
            throw PTYError.HandleCreationFailed
        }

        logger.debug("Child PTY Opened at: \(ptsPath)")
        
        return fileHandle
    }
}
