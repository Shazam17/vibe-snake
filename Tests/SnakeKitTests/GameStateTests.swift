import XCTest
@testable import SnakeKit

/// Подставной стор для детерминированных тестов.
final class FakeStore: HighScoreStore {
    var bestValue = 0
    var submitted: [Int] = []

    func best() -> Int { bestValue }

    @discardableResult
    func submit(_ score: Int) -> Bool {
        let wasRecord = score > bestValue
        if wasRecord { bestValue = score }
        submitted.append(score)
        return wasRecord
    }
}

@MainActor
final class GameStateTests: XCTestCase {

    private let initialSnake = [Point(x: 12, y: 12), Point(x: 11, y: 12), Point(x: 10, y: 12)]

    private func playUntilDeath(_ state: GameState) {
        for _ in 0..<100 {
            state.tick()
            if state.isGameOver { return }
        }
    }

    func test_initial_layout() {
        let state = GameState(store: FakeStore())
        XCTAssertEqual(state.board.snake, initialSnake)
        XCTAssertEqual(state.board.direction, Direction.right)
        XCTAssertEqual(state.score, 0)
        XCTAssertTrue(state.isRunning)
        XCTAssertFalse(state.isPaused)
        XCTAssertFalse(state.isGameOver)
    }

    func test_enqueue_reverse_ignored() {
        let state = GameState(store: FakeStore())
        XCTAssertFalse(state.enqueueTurn(Direction.left))
        XCTAssertTrue(state.pendingTurnsView.isEmpty)
    }

    // Стартовое направление .right: до первого тика в буфер принимаются только .up/.down.
    func test_buffered_turns_apply_one_per_tick() {
        let state = GameState(store: FakeStore())
        XCTAssertTrue(state.enqueueTurn(.up))
        XCTAssertTrue(state.enqueueTurn(.down))
        state.tick()
        XCTAssertEqual(state.board.direction, Direction.up)
        state.tick()
        XCTAssertEqual(state.board.direction, Direction.down)
        XCTAssertTrue(state.pendingTurnsView.isEmpty)
    }

    func test_buffer_cap_two() {
        let state = GameState(store: FakeStore())
        XCTAssertTrue(state.enqueueTurn(.up))
        XCTAssertTrue(state.enqueueTurn(.down))
        XCTAssertTrue(state.enqueueTurn(.up))
        XCTAssertEqual(state.pendingTurnsView, [.down, .up])
    }

    func test_enqueue_while_paused_is_dropped() {
        let state = GameState(store: FakeStore())
        state.togglePause()
        XCTAssertFalse(state.enqueueTurn(.up))
        state.togglePause()
        XCTAssertTrue(state.pendingTurnsView.isEmpty)
        XCTAssertEqual(state.board.direction, Direction.right)
    }

    // score 0/3 -> 8.0; score 4 -> 9.0; score 28 и 100 -> 15.0
    func test_speed_formula() {
        let state = GameState(store: FakeStore())
        state._debugSetScore(0)
        XCTAssertEqual(state.ticksPerSecond, 8.0)
        state._debugSetScore(3)
        XCTAssertEqual(state.ticksPerSecond, 8.0)
        state._debugSetScore(4)
        XCTAssertEqual(state.ticksPerSecond, 9.0)
        state._debugSetScore(28)
        XCTAssertEqual(state.ticksPerSecond, 15.0)
        state._debugSetScore(100)
        XCTAssertEqual(state.ticksPerSecond, 15.0)
    }

    func test_death_updates_store_and_freezes() {
        let store = FakeStore()
        let state = GameState(store: store)
        playUntilDeath(state)

        XCTAssertTrue(state.isGameOver)
        XCTAssertFalse(state.isRunning)
        XCTAssertEqual(store.submitted.last, state.score)
        XCTAssertEqual(state.newRecord, state.score > 0)
        XCTAssertEqual(state.best, max(0, state.score))

        // После game over тики не меняют состояние.
        let score = state.score
        let gameOver = state.isGameOver
        let newRecord = state.newRecord
        let snake = state.board.snake
        let food = state.board.food
        let direction = state.board.direction
        state.tick()
        XCTAssertEqual(state.score, score)
        XCTAssertEqual(state.isGameOver, gameOver)
        XCTAssertEqual(state.newRecord, newRecord)
        XCTAssertEqual(state.board.snake, snake)
        XCTAssertEqual(state.board.food, food)
        XCTAssertEqual(state.board.direction, direction)
    }

    func test_restart_resets() {
        let store = FakeStore()
        store.bestValue = 10
        let state = GameState(store: store)
        playUntilDeath(state)
        state.startNewGame()

        XCTAssertEqual(state.score, 0)
        XCTAssertFalse(state.newRecord)
        XCTAssertTrue(state.isRunning)
        XCTAssertFalse(state.isPaused)
        XCTAssertFalse(state.isGameOver)
        XCTAssertEqual(state.best, 10)
        XCTAssertEqual(state.board.snake, initialSnake)
        XCTAssertEqual(state.board.direction, Direction.right)
        XCTAssertTrue(state.pendingTurnsView.isEmpty)
    }
}
