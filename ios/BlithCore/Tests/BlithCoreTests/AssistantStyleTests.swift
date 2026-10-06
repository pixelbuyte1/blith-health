import Foundation
import Testing
@testable import BlithCore

struct AssistantStyleTests {
    @Test func emDashesBecomeCommas() {
        #expect(LLMAssistant.plainStyle("time\u{2014}or tensing") == "time, or tensing")
        #expect(LLMAssistant.plainStyle("a \u{2014} b") == "a, b")
    }

    @Test func rangesKeepTheirDash() {
        #expect(LLMAssistant.plainStyle("2\u{2013}4 sentences") == "2\u{2013}4 sentences")
    }
}
