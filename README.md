# PtyKit

A wrapper around PTY functionality for both Linux and macOS

![Xcode](https://img.shields.io/badge/Swift-5.4-brightgreen.svg)
[![MIT license](http://img.shields.io/badge/license-MIT-brightgreen.svg)](http://opensource.org/licenses/MIT)


### WARNING

In progress. Functionality may be limited.

### How to Use

Creating a process is somewhat similar to `Process`. The key difference is that it opens a psudeo-terminal, 
making it possible to interact with certain processes like docker containers, for example. 

It also provides some basic send/expect functionality using regular expressions to enable simple automation
of a process on the other side of the PTY. 

```
let process = try PTYProcess(executableUrl, arguments: [])
try process.run()

try process.sendLine("command to execute")
let didMatchExpect = process.expect("some result", timeout: 10.0) // Timeout after 10 seconds.

guard didMatchExpect else {
    print("Command didn't behave as expected")
    return
}
```
