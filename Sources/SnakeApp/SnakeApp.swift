import SwiftUI
import SnakeKit

@main
struct SnakeApp: App {
    let state = GameState()

    var body: some Scene {
        WindowGroup {
            GameView(state: state)
        }
        .defaultSize(width: 720, height: 780)
    }
}
