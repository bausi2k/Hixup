import Testing
@testable import HixupCore

@Suite struct ProcessNamingTests {
    @Test func fullExecutableNameComesFromThePath() {
        let path = "/Applications/Google Chrome.app/Contents/Frameworks/Helper.app/Contents/MacOS/Google Chrome Helper (Aperitif Renderer)"
        #expect(ProcessNaming.displayName(path: path, fallback: "Google Chrome Helper (Aperitif :") == "Google Chrome Helper (Aperitif Renderer)")
    }

    @Test func missingPathFallsBackToTheShortName() {
        #expect(ProcessNaming.displayName(path: "", fallback: "launchd") == "launchd")
        #expect(ProcessNaming.displayName(path: nil, fallback: "kernel") == "kernel")
    }

    @Test func emptyNamesGetAPidLabel() {
        #expect(ProcessNaming.displayName(path: nil, fallback: "", pid: 42) == "pid 42")
    }
}
