import SwiftUI
import SnakeKit

struct GameView: View {
    let state: GameState
    @State private var clock = GameClock()
    @State private var monitor: Any?

    private let hudHeight: CGFloat = 40

    var body: some View {
        VStack(spacing: 0) {
            hud
            // TimelineView перерисовывает канвас каждый кадр — Canvas сам не
            // отслеживает @Observable-чтения; оверлеи рядом, в SwiftUI-частях
            // трекинг работает штатно.
            TimelineView(.animation) { _ in
                ZStack {
                    Canvas { context, size in
                        drawBoard(in: &context, size: size)
                    }
                    overlays
                }
            }
        }
        .frame(minWidth: 300, minHeight: 340)
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

    /// HUD: «Score: N» слева, «Best: M» справа; monospacedDigit, 15 pt.
    private var hud: some View {
        HStack {
            Text("Score: \(state.score)")
            Spacer()
            Text("Best: \(state.best)")
        }
        .font(.system(size: 15))
        .monospacedDigit()
        .padding(.horizontal, 12)
        .frame(height: hudHeight)
        .background(Color(white: 0.97))
    }

    @ViewBuilder
    private var overlays: some View {
        if state.isGameOver {
            VStack(spacing: 8) {
                Text("Game over")
                    .font(.title)
                    .bold()
                Text("Score: \(state.score)")
                    .font(.title3)
                if state.newRecord {
                    Text("New best!")
                        .font(.title3)
                        .bold()
                        .foregroundStyle(.orange)
                }
                Text("Enter to restart")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 16))
        } else if state.isPaused {
            Text("Paused — Space to resume")
                .font(.title3)
                .padding(20)
                .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
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

    private func drawBoard(in context: inout GraphicsContext, size: CGSize) {
        let cols = CGFloat(state.board.columns)
        let rows = CGFloat(state.board.rows)
        let cell = min(size.width / cols, size.height / rows)
        let ox = (size.width - cell * cols) / 2
        let oy = (size.height - cell * rows) / 2

        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.97)))

        // Сетка — только когда клетка ≥ 8 pt, иначе шумит.
        if cell >= 8 {
            var grid = Path()
            for i in 0...Int(cols) {
                let x = ox + CGFloat(i) * cell
                grid.move(to: CGPoint(x: x, y: oy))
                grid.addLine(to: CGPoint(x: x, y: oy + cell * rows))
            }
            for j in 0...Int(rows) {
                let y = oy + CGFloat(j) * cell
                grid.move(to: CGPoint(x: ox, y: y))
                grid.addLine(to: CGPoint(x: ox + cell * cols, y: y))
            }
            context.stroke(grid, with: .color(.black.opacity(0.06)), lineWidth: 1)
        }

        for (index, segment) in state.board.snake.enumerated() {
            let rect = CGRect(x: ox + CGFloat(segment.x) * cell,
                              y: oy + CGFloat(segment.y) * cell,
                              width: cell, height: cell)
            let color: Color = index == 0
                ? Color(red: 0.0, green: 0.55, blue: 0.20)   // голова
                : Color(red: 0.35, green: 0.78, blue: 0.40)  // тело
            context.fill(Path(roundedRect: rect.insetBy(dx: cell * 0.08, dy: cell * 0.08),
                              cornerRadius: cell * 0.30),
                         with: .color(color))
        }

        let food = state.board.food
        let radius = cell * 0.36
        let center = CGPoint(x: ox + (CGFloat(food.x) + 0.5) * cell,
                             y: oy + (CGFloat(food.y) + 0.5) * cell)
        context.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                            width: radius * 2, height: radius * 2)),
                     with: .color(.red))
    }
}
