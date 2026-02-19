import Foundation
@testable import ImprovBuddy

enum TheoryTestSupport {
    static func knowledgeBase() -> TheoryKnowledgeBase {
        TheoryKnowledgeBase.load(bundle: .main)
    }

    static func resolver() -> TheoryResolver {
        TheoryResolver(knowledgeBase: knowledgeBase())
    }
}
