import SwiftUI
import SnakeKit

struct GameView: View {
    let state: GameState
    @State private var clock = GameClock()

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
        }
        .onDisappear {
            clock.stop()
        }
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
