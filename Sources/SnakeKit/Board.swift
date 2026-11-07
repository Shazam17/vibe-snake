import Foundation

public struct Point: Hashable, Equatable {
    public let x: Int
    public let y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
}

public enum Direction {
    case up, down, left, right

    /// Сдвиг головы на один тик в этом направлении (координаты 0-based, y растёт вниз).
    public var offset: SIMD2<Int> {
        switch self {
        case .up: SIMD2(0, -1)
        case .down: SIMD2(0, 1)
        case .left: SIMD2(-1, 0)
        case .right: SIMD2(1, 0)
        }
    }
}

public enum StepOutcome {
    case progressed
    case ateFood
    case hitWall
    case hitSelf
    case boardFull
}

public struct Board {
    public let columns: Int
    public let rows: Int
    /// Змейка; head — первый элемент массива.
    public var snake: [Point]
    public var direction: Direction
    public var food: Point

    /// Стандартная стартовая раскладка (змейка из 3 клеток по центру, движется вправо);
    /// первая еда спавнится системным RNG в случайной свободной клетке.
    public init(columns: Int = 25, rows: Int = 25) {
        self.columns = columns
        self.rows = rows
        let cx = columns / 2
        let cy = rows / 2
        self.snake = [Point(x: cx, y: cy), Point(x: cx - 1, y: cy), Point(x: cx - 2, y: cy)]
        self.direction = .right
        var rng = SystemRandomNumberGenerator()
        let free = Self.freeCells(excluding: self.snake, in: columns, rows: rows)
        self.food = free[Int.random(in: 0..<free.count, using: &rng)]
    }

    /// Тестовая полная раскладка — без RNG.
    public init(columns: Int, rows: Int, snake: [Point], direction: Direction, food: Point) {
        self.columns = columns
        self.rows = rows
        self.snake = snake
        self.direction = direction
        self.food = food
    }

    /// Один тик. Фиксированный порядок:
    /// 1. newHead = head + offset; вне границ → .hitWall, без мутаций.
    /// 2. ate = (newHead == food); тело для проверки: ate ? snake : snake без последнего.
    /// 3. newHead ∈ тела → .hitSelf, без мутаций.
    /// 4. insert(newHead, at: 0); если !ate — removeLast().
    /// 5. Если ate: спавн еды в случайной свободной клетке через rng; свободных нет → .boardFull
    ///    (рост всё же применяется); иначе .ateFood. Иначе .progressed.
    public mutating func step<RNG: RandomNumberGenerator>(using rng: inout RNG) -> StepOutcome {
        let head = snake[0]
        let offset = direction.offset
        let newHead = Point(x: head.x + offset.x, y: head.y + offset.y)

        guard (0..<columns).contains(newHead.x), (0..<rows).contains(newHead.y) else {
            return .hitWall
        }

        let ate = (newHead == food)
        let bodyForCheck = ate ? snake : Array(snake.dropLast())
        if bodyForCheck.contains(newHead) {
            return .hitSelf
        }

        snake.insert(newHead, at: 0)
        if !ate {
            snake.removeLast()
        }

        guard ate else {
            return .progressed
        }

        let free = Self.freeCells(excluding: snake, in: columns, rows: rows)
        guard !free.isEmpty else {
            return .boardFull
        }
        food = free[Int.random(in: 0..<free.count, using: &rng)]
        return .ateFood
    }

    private static func freeCells(excluding occupied: [Point], in columns: Int, rows: Int) -> [Point] {
        let taken = Set(occupied)
        var free: [Point] = []
        free.reserveCapacity(columns * rows - occupied.count)
        for y in 0..<rows {
            for x in 0..<columns where !taken.contains(Point(x: x, y: y)) {
                free.append(Point(x: x, y: y))
            }
        }
        return free
    }
}
