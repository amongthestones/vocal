import XCTest
@testable import Vocal

final class TextRulesTests: XCTestCase {
    func testParseSkipsCommentsAndBadLines() {
        let parsed = TextRules.parseReplacements("""
            # comment
            Castus => Castos

            no arrow here
            Coruna=>Coruña
            """)
        XCTAssertEqual(parsed, [
            .init(heard: "Castus", written: "Castos"),
            .init(heard: "Coruna", written: "Coruña"),
        ])
    }

    func testReplacesWholeWordsInAnyCase() {
        let rules = TextRules(replacements: [.init(heard: "castus", written: "Castos")])
        XCTAssertEqual(rules.apply(to: "Send the Castus draft"), "Send the Castos draft")
        XCTAssertEqual(rules.apply(to: "Castusville is fine"), "Castusville is fine")
    }

    func testWordBoundariesWorkWithAccents() {
        let rules = TextRules(replacements: [.init(heard: "Coruna", written: "Coruña")])
        XCTAssertEqual(rules.apply(to: "it's in Coruna, near Ferrol"), "it's in Coruña, near Ferrol")
        XCTAssertEqual(rules.apply(to: "Corunés"), "Corunés")
    }

    func testLongerReplacementsWin() {
        let rules = TextRules(replacements: [
            .init(heard: "Sacra", written: "SACRA"),
            .init(heard: "Ribera Sacra", written: "Ribeira Sacra"),
        ])
        XCTAssertEqual(rules.apply(to: "to the Ribera Sacra today"), "to the Ribeira Sacra today")
    }

    func testDollarSignsInReplacementAreLiteral() {
        let rules = TextRules(replacements: [.init(heard: "ten bucks", written: "$10")])
        XCTAssertEqual(rules.apply(to: "it was ten bucks"), "it was $10")
    }

    func testFillersOffByDefault() {
        XCTAssertEqual(TextRules().apply(to: "Okay, uh, I would"), "Okay, uh, I would")
    }

    func testRemovesFillersAndTidiesCommas() {
        let rules = TextRules(removeFillers: true)
        XCTAssertEqual(rules.apply(to: "Okay, uh, I would also like"), "Okay, I would also like")
        XCTAssertEqual(rules.apply(to: "Okay, uh I would also like"), "Okay, I would also like")
        XCTAssertEqual(rules.apply(to: "so um we can go"), "so we can go")
    }

    func testCapitalizesAfterFillerAtSentenceStart() {
        let rules = TextRules(removeFillers: true)
        XCTAssertEqual(rules.apply(to: "Uh, so we go."), "So we go.")
        XCTAssertEqual(rules.apply(to: "Done. Um, next thing."), "Done. Next thing.")
    }

    func testRemovesGalicianFillers() {
        let rules = TextRules(removeFillers: true)
        XCTAssertEqual(rules.apply(to: "Pois, eh, non sei hum se vou"), "Pois, non sei se vou")
    }

    func testKeepsWordsThatContainFillers() {
        let rules = TextRules(removeFillers: true)
        XCTAssertEqual(rules.apply(to: "the umbrella and the hummus"), "the umbrella and the hummus")
    }

    func testFillerBeforePunctuation() {
        let rules = TextRules(removeFillers: true)
        XCTAssertEqual(rules.apply(to: "I think, um."), "I think.")
    }
}
