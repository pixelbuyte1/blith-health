import Foundation
import Testing
@testable import BlithCore

@Suite("Ask body notes")
struct BodyNoteProposalTests {
    func tools() -> HealthAssistantTools {
        HealthAssistantTools(snapshot: HealthSnapshot.build(history: T.history(steps: T.constant(6000, days: 0...40)),
                                                            profile: UserProfile(), now: T.now, calendar: T.calendar))
    }

    @Test func proposalIsACardAndSavesNothing() {
        let tools = tools()
        let yesterday = T.today.adding(days: -1)
        let out = tools.execute(name: "propose_body_note", arguments: [
            "region": "rightAnkle", "title": "Rolled right ankle", "date": .string(yesterday.description), "kind": "injury",
        ])
        guard case .bodyNoteProposal(let note)? = out.blocks.first else { Issue.record("expected a proposal block"); return }
        #expect(note.bodyRegion == .rightAnkle)
        #expect(note.date == yesterday)
        #expect(note.kind == .injury)
        #expect(note.resolvedDate == nil)
        #expect(out.blocks.first?.link == nil)
        #expect(out.result["saved"] == .bool(false))
        #expect(tools.snapshot.ctx.history.events.isEmpty)
    }

    @Test func proposalClampsFutureDatesAndRejectsBadInput() {
        let tools = tools()
        let future = tools.execute(name: "propose_body_note", arguments: [
            "region": "Left knee", "title": "Knee stiff", "date": .string(T.today.adding(days: 3).description),
        ])
        guard case .bodyNoteProposal(let note)? = future.blocks.first else { Issue.record("expected a proposal block"); return }
        #expect(note.date == T.today)
        #expect(note.bodyRegion == .leftKnee)
        #expect(tools.execute(name: "propose_body_note", arguments: ["region": "elbowish", "title": "x"]).blocks.isEmpty)
        #expect(tools.execute(name: "propose_body_note", arguments: ["region": "neck", "title": "  "]).result["error"] != nil)
    }

    @Test func regionsAreFoundInPlainWords() {
        #expect(BodyRegion.match(in: "I rolled my right ankle yesterday") == .region(.rightAnkle))
        #expect(BodyRegion.match(in: "right now my left knee aches") == .region(.leftKnee))
        #expect(BodyRegion.match(in: "my knee hurts") == .needsSide("knee"))
        #expect(BodyRegion.match(in: "lower back is tight") == .region(.lowerBack))
        #expect(BodyRegion.match(in: "my hips are sore") == .region(.hips))
        #expect(BodyRegion.match(in: "I walked 5 km") == nil)
    }

    @Test func localAssistantProposesOrAsksForTheSide() async throws {
        let local = LocalAssistant(tools: tools())
        let reply = try await local.respond(to: "I sprained my left wrist", history: []) { _ in }
        #expect(reply.blocks.map(\.kind) == ["bodyNoteProposal"])
        let ask = try await local.respond(to: "my ankle hurts", history: []) { _ in }
        #expect(ask.blocks.isEmpty)
        #expect(ask.text.contains("left or right"))
    }
}
