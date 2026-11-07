import Foundation
import XCTest
import SnakeKit

final class HighScoreStoreTests: XCTestCase {

    private func freshStore(_ label: String) -> UserDefaultsHighScoreStore {
        let defaults = UserDefaults(suiteName: label)!
        defaults.removeObject(forKey: "snake.best.score") // изоляция между прогонами
        return UserDefaultsHighScoreStore(defaults: defaults)
    }

    func test_fresh_store_best_is_zero() {
        let store = freshStore(#function)
        XCTAssertEqual(store.best(), 0)
    }

    func test_submit_new_record_persists() {
        let store = freshStore(#function)
        XCTAssertTrue(store.submit(7))
        XCTAssertEqual(store.best(), 7)

        // Второй инстанс того же UserDefaults видит тот же рекорд.
        let second = UserDefaultsHighScoreStore(defaults: UserDefaults(suiteName: #function)!)
        XCTAssertEqual(second.best(), 7)
        XCTAssertFalse(second.submit(3))
        XCTAssertEqual(second.best(), 7)
        XCTAssertFalse(second.submit(7))
        XCTAssertEqual(second.best(), 7)
    }
}
