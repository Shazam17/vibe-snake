import XCTest
import SnakeKit

/// Детерминированный RNG для тестов (splitmix64).
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

final class BoardTests: XCTestCase {

    // Тест-вспомогательный RNG, чтобы вызов `step(using:)` был детерминирован.
    private func rng(seed: UInt64 = 42) -> SplitMix64 { SplitMix64(seed: seed) }

    func test_step_moves_head_one_cell() {
        var board = Board(columns: 5, rows: 5,
                          snake: [Point(x: 2, y: 2), Point(x: 1, y: 2)],
                          direction: .right, food: Point(x: 4, y: 0))
        var g = rng()
        let outcome = board.step(using: &g)
        XCTAssertEqual(outcome, StepOutcome.progressed)
        XCTAssertEqual(board.snake[0], Point(x: 3, y: 2))
        XCTAssertEqual(board.snake.count, 2)
    }

    func test_hit_wall_no_mutation() {
        let initialSnake = [Point(x: 4, y: 2), Point(x: 3, y: 2)]
        var board = Board(columns: 5, rows: 5,
                          snake: initialSnake, direction: .right, food: Point(x: 0, y: 0))
        var g = rng()
        let outcome = board.step(using: &g)
        XCTAssertEqual(outcome, StepOutcome.hitWall)
        XCTAssertEqual(board.snake, initialSnake)
        XCTAssertEqual(board.food, Point(x: 0, y: 0))
    }

    func test_hit_self() {
        let initialSnake = [Point(x: 2, y: 2), Point(x: 2, y: 3), Point(x: 3, y: 3), Point(x: 3, y: 2)]
        var board = Board(columns: 5, rows: 5,
                          snake: initialSnake, direction: .down, food: Point(x: 0, y: 4))
        var g = rng()
        let outcome = board.step(using: &g)
        XCTAssertEqual(outcome, StepOutcome.hitSelf)
        XCTAssertEqual(board.snake, initialSnake)
    }

    // Review Focus #1: ход в клетку, которую хвост покидает в этом же тике (без роста).
    func test_move_into_vacating_tail_is_safe() {
        var board = Board(columns: 5, rows: 5,
                          snake: [Point(x: 0, y: 0), Point(x: 0, y: 1), Point(x: 1, y: 1), Point(x: 1, y: 0)],
                          direction: .right, food: Point(x: 4, y: 4))
        var g = rng()
        let outcome = board.step(using: &g)
        XCTAssertEqual(outcome, StepOutcome.progressed)
        XCTAssertEqual(board.snake.count, 4)
        XCTAssertEqual(board.snake, [Point(x: 1, y: 0), Point(x: 0, y: 0), Point(x: 0, y: 1), Point(x: 1, y: 1)])
    }

    func test_eat_grows_and_spawns_off_snake() {
        var board = Board(columns: 5, rows: 5,
                          snake: [Point(x: 1, y: 1), Point(x: 0, y: 1)],
                          direction: .right, food: Point(x: 2, y: 1))
        var g = rng(seed: 7)
        let outcome = board.step(using: &g)
        XCTAssertEqual(outcome, StepOutcome.ateFood)
        XCTAssertEqual(board.snake.count, 3)
        XCTAssertFalse(board.snake.contains(board.food))
    }

    // Review Focus #3 (частично): инвариант спавна на 500 тиков с детерминированным RNG.
    func test_spawn_invariant_500_ticks() {
        var board = Board(columns: 8, rows: 8)
        var rngGen = SplitMix64(seed: 42)
        for _ in 0..<500 {
            let outcome = board.step(using: &rngGen)
            switch outcome {
            case .hitWall, .hitSelf, .boardFull:
                return // игра завершилась — инварианты проверялись, пока она была жива
            case .progressed, .ateFood:
                XCTAssertFalse(board.snake.contains(board.food))
            }
        }
    }

    // Review Focus #3: доска заполнена после поедания последней клетки.
    func test_board_full_is_draw_without_spawn() {
        var board = Board(columns: 2, rows: 2,
                          snake: [Point(x: 1, y: 0), Point(x: 1, y: 1), Point(x: 0, y: 1)],
                          direction: .left, food: Point(x: 0, y: 0))
        var g = rng(seed: 1)
        let outcome = board.step(using: &g)
        XCTAssertEqual(outcome, StepOutcome.boardFull)
        // Еда не заспавнилась повторно (осталась в той же клетке — теперь под змейкой).
        XCTAssertEqual(board.food, Point(x: 0, y: 0))
        XCTAssertEqual(board.snake.count, 4)
    }

    func test_default_init_layout() {
        let board = Board(columns: 25, rows: 25)
        XCTAssertEqual(board.snake, [Point(x: 12, y: 12), Point(x: 11, y: 12), Point(x: 10, y: 12)])
        XCTAssertEqual(board.direction, Direction.right)
        XCTAssertFalse(board.snake.contains(board.food))
    }
}
