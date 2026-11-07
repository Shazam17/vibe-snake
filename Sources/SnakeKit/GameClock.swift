import Foundation

/// Ведёт тики: пока `state.isRunning && !state.isGameOver` — сон 1/ticksPerSecond,
/// затем `state.tick()` (если не пауза).
@MainActor
public final class GameClock {
    private var task: Task<Void, Never>?

    public init() {}

    /// Перезапуск цикла: останавливает старый (если был) и запускает новый.
    public func start(state: GameState) {
        stop()
        task = Task {
            while state.isRunning && !state.isGameOver {
                try? await Task.sleep(for: .seconds(1.0 / state.ticksPerSecond))
                if !state.isPaused {
                    state.tick()
                }
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }
}
