import SwiftUI
import SnakeKit

struct GameView: View {
    let state: GameState
    @State private var clock = GameClock()
    @State private var monitor: Any?

    var body: some View {
        // TimelineView перерисовывает канвас каждый кадр — канвас сам по себе
        // не отслеживает @Observable-чтения, поэтому явная подтяжка кадров нужна.
        TimelineView(.animation) { _ in
            Canvas { context, size in
                drawBoard(in: &context, size: size)
            }
        }
        .background(Color.black)
        .onAppear {
            clock.start(state: state)
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                // Монитор срабатывает на главном потоке; Swift 6 требует явного
                // входа в MainActor-контекст из non-isolated-замыкания, а его
                // @Sendable-тело не может захватить non-Sendable NSEvent —
                // передаём только keyCode.
                let code = Int(event.keyCode)
                let consumed = MainActor.assumeIsolated {
                    handleKey(code: code)
                }
                return consumed ? nil : event
            }
        }
        .onDisappear {
            clock.stop()
            if let m = monitor {
                NSEvent.removeMonitor(m)
            }
            monitor = nil
        }
    }

    /// Правила ввода: true = ключ съеден (ни системного бипа, ни прохода дальше).
    /// При game over: Enter/space → рестарт. В игре: направление → буфер, space → пауза.
    /// Остальные коды не глотаются.
    @MainActor
    private func handleKey(code: Int) -> Bool {
        if state.isGameOver {
            if code == InputMapping.restartKeyCode || code == InputMapping.pauseKeyCode {
                state.startNewGame()
                clock.start(state: state)
                return true
            }
            return false
        }
        if code == InputMapping.pauseKeyCode {
            state.togglePause()
            return true
        }
        if let d = InputMapping.direction(forKeyCode: code) {
            state.enqueueTurn(d)
            return true
        }
        return false
    }

    /// Размер клетки: min(W, H − HUD) / размер доски. HUD = 40 pt сверху.
    private func drawBoard(in context: inout GraphicsContext, size: CGSize) {
        let hud: CGFloat = 40
        let cols = CGFloat(state.board.columns)
        let rows = CGFloat(state.board.rows)
        let cell = min(size.width / cols, (size.height - hud) / rows)

        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))

        for segment in state.board.snake {
            let rect = CGRect(x: CGFloat(segment.x) * cell,
                              y: hud + CGFloat(segment.y) * cell,
                              width: cell, height: cell)
            context.fill(Path(roundedRect: rect.insetBy(dx: 1, dy: 1), cornerRadius: cell * 0.25),
                         with: .color(.white))
        }

        let food = state.board.food
        let radius = cell * 0.36
        let center = CGPoint(x: (CGFloat(food.x) + 0.5) * cell,
                             y: hud + (CGFloat(food.y) + 0.5) * cell)
        context.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                            width: radius * 2, height: radius * 2)),
                     with: .color(.red))
    }
}
