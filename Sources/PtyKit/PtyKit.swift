import Foundation

import Cstdlib

public enum PtyError: Error {
    case OpenFailed
    case GrantFailed
    case UnlockFailed
    case HandleCreationFailed
}

extension FileHandle {
    public static func openPty() throws -> FileHandle {
        let hostDescriptor = Cstdlib.posix_openpt(Cstdlib.O_RDWR)
        guard -1 != hostDescriptor else {
            throw PtyError.OpenFailed
        }

        return FileHandle(fileDescriptor: hostDescriptor)
    }

    public func getChildPty() throws -> FileHandle {
        let hostDescriptor = self.fileDescriptor
        guard 0 == Cstdlib.grantpt(hostDescriptor) else {
            throw PtyError.GrantFailed
        }

        guard 0 == Cstdlib.unlockpt(hostDescriptor) else {
            throw PtyError.UnlockFailed
        }

        let childDescriptor = String(cString: Cstdlib.ptsname(hostDescriptor))

        guard let fileHandle = FileHandle(forUpdatingAtPath: childDescriptor) else {
            throw PtyError.HandleCreationFailed
        }

        return fileHandle
    }
}
