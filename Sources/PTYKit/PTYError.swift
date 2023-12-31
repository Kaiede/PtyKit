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

enum PTYError: Error {
    // PTY Creation Errors
    case grantFailed
    case handleCreationFailed
    case unlockFailed

    // PTY Read Errors
    case invalidData

    // Process Attachment Errors
    case alreadyAttached
    case notAttached
}

extension PTYError: CustomStringConvertible {
    var description: String {
        switch self {
        case .grantFailed: return "PTY could not be granted"
        case .handleCreationFailed: return "PTY file handle could not be created"
        case .unlockFailed: return "PTY could not be unlocked"
        case .invalidData: return "UTF8 data could not be generated for string"
        case .alreadyAttached: return "PTY already has a process attached"
        case .notAttached: return "PTY isn't attached to this process"
        }
    }
}

extension PTYError {
    var localizedDescription: String { description }
}
