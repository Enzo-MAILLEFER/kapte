import Foundation

let historyURL = kapteDir.appendingPathComponent("history.json")

/// Dernières réponses (la plus récente en premier), gardées dans ~/.kapte/history.json.
final class History {
    static let maxEntries = 30

    private(set) var answers: [String]

    init() {
        answers = (try? Data(contentsOf: historyURL))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String] } ?? []
    }

    func add(_ answer: String) {
        answers.insert(answer, at: 0)
        answers = Array(answers.prefix(History.maxEntries))
        if let data = try? JSONSerialization.data(withJSONObject: answers) {
            try? data.write(to: historyURL, options: .atomic)
        }
    }
}
