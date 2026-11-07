import Foundation
import Observation

@MainActor
@Observable
public final class GameState {
    public private(set) var board: Board
    public private(set) var score = 0
    public private(set) var best: Int
    public private(set) var isRunning = false
    public private(set) var isPaused = false
    public private(set) var isGameOver = false
    public private(set) var newRecord = false

    private let columns: Int
    private let rows: Int
    private let store: HighScoreStore
    @ObservationIgnored private var rng = SystemRandomNumberGenerator()
    @ObservationIgnored private var pendingTurns: [Direction]

    public init(store: HighScoreStore = UserDefaultsHighScoreStore(), columns: Int = 25, rows: Int = 25) {
        self.columns = columns
        self.rows = rows
        self.store = store
        self.board = Board(columns: columns, rows: rows)
        self.best = store.best()
        self.pendingTurns = []
        startNewGame()
    }

    public func startNewGame() {
        board = Board(columns: columns, rows: rows)
        score = 0
        pendingTurns.removeAll()
        isPaused = false
        isGameOver = false
        newRecord = false
        isRunning = true
    }

    public func togglePause() {
        guard isRunning, !isGameOver else { return }
        isPaused.toggle()
    }

    /// Буфер до 2 направлений: обратное/текущее игнорируется, переполнение выбрасывает старейшее.
    @discardableResult
    public func enqueueTurn(_ d: Direction) -> Bool {
        guard isRunning, !isPaused else { return false }
        if d == board.direction || Self.opposite(d) == board.direction { return false }
        if pendingTurns.count >= 2 { pendingTurns.removeFirst() }
        pendingTurns.append(d)
        return true
    }

    /// Доступ к буферу поворотов для тестов.
    public var pendingTurnsView: [Direction] { pendingTurns }

    public var ticksPerSecond: Double { Double(min(8 + score / 4, 15)) }

    /// Тестовая поддержка: задать счёт без поедания еды (для проверки формулы скорости).
    internal func _debugSetScore(_ value: Int) { score = value }

    public func tick() {
        guard isRunning, !isGameOver, !isPaused else { return }
        if let d = pendingTurns.first {
            pendingTurns.removeFirst()
            board.direction = d
        }
        switch board.step(using: &rng) {
        case .progressed:
            break
        case .ateFood:
            score += 1
        case .hitWall, .hitSelf, .boardFull:
            isGameOver = true
            isRunning = false
            newRecord = store.submit(score)
            best = Swift.max(best, score)
        }
    }

    private static func opposite(_ d: Direction) -> Direction {
        switch d {
        case .up: return .down
        case .down: return .up
        case .left: return .right
        case .right: return .left
        }
    }
}
