import XCTest
@testable import ImprovBuddy

final class TheoryDatasetLoadTests: XCTestCase {
    func testSchemaAndChecksumValidation() {
        let knowledgeBase = TheoryTestSupport.knowledgeBase()

        XCTAssertEqual(knowledgeBase.envelope.schemaVersion, 1)
        XCTAssertEqual(
            knowledgeBase.envelope.checksumSHA256.lowercased(),
            knowledgeBase.checksum.lowercased()
        )
        XCTAssertTrue(knowledgeBase.validationIssues.isEmpty, knowledgeBase.validationIssues.joined(separator: "\n"))
    }

    func testIdentifiersAreUnique() {
        let dataset = TheoryTestSupport.knowledgeBase().envelope.dataset

        XCTAssertEqual(Set(dataset.scales.map(\.id)).count, dataset.scales.count)
        XCTAssertEqual(Set(dataset.chords.map(\.id)).count, dataset.chords.count)
        XCTAssertEqual(Set(dataset.arpeggios.map(\.id)).count, dataset.arpeggios.count)
        XCTAssertEqual(Set(dataset.recommendations.map(\.id)).count, dataset.recommendations.count)
        XCTAssertEqual(Set(dataset.guideToneRules.map(\.id)).count, dataset.guideToneRules.count)
        XCTAssertEqual(Set(dataset.avoidToneRules.map(\.id)).count, dataset.avoidToneRules.count)
        XCTAssertEqual(Set(dataset.voiceLeadingRules.map(\.id)).count, dataset.voiceLeadingRules.count)
    }

    func testRecommendationReferencesResolve() {
        let dataset = TheoryTestSupport.knowledgeBase().envelope.dataset
        let scales = Set(dataset.scales.map(\.id))
        let arpeggios = Set(dataset.arpeggios.map(\.id))
        let chords = Set(dataset.chords.map(\.id))
        let guides = Set(dataset.guideToneRules.map(\.id))
        let avoids = Set(dataset.avoidToneRules.map(\.id))
        let voiceLeading = Set(dataset.voiceLeadingRules.map(\.id))

        for recommendation in dataset.recommendations {
            XCTAssertTrue(chords.contains(recommendation.chordID), recommendation.id)
            XCTAssertTrue(scales.contains(recommendation.primaryScaleID), recommendation.id)
            XCTAssertTrue(Set(recommendation.alternativeScaleIDs).isSubset(of: scales), recommendation.id)
            XCTAssertTrue(Set(recommendation.arpeggioIDs).isSubset(of: arpeggios), recommendation.id)

            if let id = recommendation.guideToneRuleID {
                XCTAssertTrue(guides.contains(id), recommendation.id)
            }

            XCTAssertTrue(Set(recommendation.avoidToneRuleIDs).isSubset(of: avoids), recommendation.id)
            XCTAssertTrue(Set(recommendation.voiceLeadingRuleIDs).isSubset(of: voiceLeading), recommendation.id)
        }
    }
}
