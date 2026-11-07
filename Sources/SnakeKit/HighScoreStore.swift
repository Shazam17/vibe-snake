import Foundation

public protocol HighScoreStore {
    func best() -> Int
    /// true, если `score` стал новым рекордом (старое значение > 0 либо score > old).
    @discardableResult
    func submit(_ score: Int) -> Bool
}

public struct UserDefaultsHighScoreStore: HighScoreStore {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "snake.best.score") {
        self.defaults = defaults
        self.key = key
    }

    public func best() -> Int {
        defaults.integer(forKey: key)
    }

    @discardableResult
    public func submit(_ score: Int) -> Bool {
        let previous = best()
        guard score > previous else { return false }
        defaults.set(score, forKey: key)
        return true
    }
}
