import XCTest
@testable import PTYKit

final class DebuggerTests: XCTestCase {
    func testSingleLaunch() {
        do {
            let shBinaryPath = URL(fileURLWithPath: "/bin/sh")
            let process = try PTYProcess(shBinaryPath, arguments: [])
            try process.run()

            try process.sendLine("echo Hello World")
            if process.expect("Hello World") == .noMatch {
                XCTFail("Expect failed")
            }

            process.terminate()
        } catch let error {
            XCTFail("\(error.localizedDescription)")
        }
    }

    func testMultipleLaunches() {
        do {
            for _ in 1...256 {
                let shBinaryPath = URL(fileURLWithPath: "/bin/sh")
                let process = try PTYProcess(shBinaryPath, arguments: [])
                try process.run()

                try process.sendLine("echo Hello World")
                if process.expect("Hello World") == .noMatch {
                    XCTFail("Expect failed")
                }

                process.terminate()
            }
        } catch let error {
            XCTFail("\(error.localizedDescription)")
        }
    }
}
