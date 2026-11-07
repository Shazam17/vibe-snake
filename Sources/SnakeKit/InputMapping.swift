public enum InputMapping {
    /// Space — пауза/продолжить.
    public static let pauseKeyCode = 49
    /// Return — рестарт после game over.
    public static let restartKeyCode = 36

    /// keyCode → направление. Стрелки + WASD (macOS virtual key codes).
    public static func direction(forKeyCode code: Int) -> Direction? {
        switch code {
        case 123, 0:  return .left
        case 124, 2:  return .right
        case 125, 1:  return .down
        case 126, 17: return .up
        default: return nil
        }
    }
}
