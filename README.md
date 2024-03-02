# PtyKit

A wrapper around PTY functionality for both Linux and macOS

![Xcode](https://img.shields.io/badge/Swift-5.4-brightgreen.svg)
[![MIT license](http://img.shields.io/badge/license-MIT-brightgreen.svg)](http://opensource.org/licenses/MIT)

### WARNING

In progress. Functionality may be limited.

### How to Use

A PsudeoTerminal creates a PTY on the system, which can then be connected to for read/write. Included is a convenience
initializer for Process that does the connect/disconnect for you, and let you send input and listen/expect output for
automation purposes.

For example, this can be used to do some basic automation of a shell.

```
let executableUrl = URL(fileURLWithPath: "/bin/sh")
let terminal = try PsudeoTerminal()
let process = Process(executableUrl, arguments: [], terminal: terminal)
try process.run()

try terminal.sendLine("whoami")

let result = terminal.expect(NSUserName(), timeout: 10.0) // Timeout after 10 seconds.
guard result != .noMatch else {
    print("Command didn't behave as expected")
    return
}
```

Another approach is that you can use the FileHandle to create connections yourself.

```
    let terminal = try PsudeoTerminal()
    let channel = try terminal.connect()

    let bootstrap = NIOPipeBootstrap(group: eventLoop)
    bootstrap
        .channelInitializer { channel in /* ... */ }
        // Must duplicate descriptor to avoid NIO closing the PTY handle directly.
        .takingOwnershipOfDescriptor(inputOutput: dup(channel.fileDescriptor))

    // When finished, you will need to close the channel:
    channel.close()
```
