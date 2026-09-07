# Running the regression suite

Use the shared RocketLaunch scheme in Xcode, select an iPhone simulator, then Product → Test (Cmd-U). Tests live in RocketLaunchTests and are members of the RocketLaunchTests target.

If simulator services are unavailable, `python3 Tests/run-host-tests.py` executes those same XCTest source files on macOS against the actual Model/ViewModel sources. It generates a temporary package and cleans it after execution. This is supplementary evidence, not a SwiftUI/iOS runtime test.

The test fixture is a fixed legacy API response. Network tests use ephemeral sessions and URLProtocol fixtures. Tests named Legacy intentionally expose existing defects; update them to enforce corrected behaviour when the approved migration fix is made.
