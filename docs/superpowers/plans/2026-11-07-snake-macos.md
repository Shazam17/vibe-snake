# «Змейка» для macOS — план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Играбельный классический «Змейку» как нативное macOS-приложение (SwiftUI + Canvas) с сохранением рекорда.

**Architecture:** Чистая игровая логика вынесена в библиотеку `SnakeKit` (value-type `Board`, движок `GameState` — `@MainActor @Observable`), UI — тонкий слой SwiftUI-исполняемого таргета `SnakeApp`: один `Canvas` рисует состояние по тикам, async-цикл на MainActor ведёт время. Тесты XCTest только для логики; рендер проверяется ручными прогонами.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI, Swift Package Manager (нет Xcode-проекта: `swift build` / `swift test` / `swift run`), XCTest, macOS 14+.

**Spec:** `docs/superpowers/specs/2026-11-07-snake-macos-design.md`

## Global Constraints

- Deployment target: **macOS 14.0** — в манифесте ровно `platforms: [.macOS(.v14)]`.
- Никаких сторонних зависимостей: только Apple SDK + XCTest/SPM. Нет SPM-пакетов, нет Xcodegen.
- Swift 6 strict concurrency: весь мутируемый игровой состояние живёт на `@MainActor`; кросс-actor передавать запрещено.
- Логическая сетка фиксированная **25×25**; стартовая змейка — 3 клетки по центру, движется вправо: head `(12,12)`, body `(11,12),(10,12)` (координаты 0-based).
- Формула скорости: `ticksPerSecond = min(8 + score / 4, 15)` (целочисленное деление); интервал тика = `1/tps` секунд.
- KeyCodes (Carbon HISS): left=123, right=124, down=125, up=126; WASD: a=0, s=1, d=2, w=17; pause=space 49; restart при game over = return 36 (и space).
- Ключ UserDefaults для рекорда: `"snake.best.score"`.
- UI-тексты — английские короткие строки («Score», «Best», «Paused…», «Game over»).

## Review Focus

Пять входных классов, которые не покрываются unit-тестами напрямую или требуют явной пробы; тест/проба добавлены в владеющую задачу:

1. Ход головы в клетку, которую хвост покидает **в этом же тике** (без роста) → выживание; с ростом — смерть. Тест: `BoardTests.test_move_into_vacating_tail_is_safe` (Task 2).
2. Двойной тап двух направлений за один тик → применяется одно в этом тике, второе в следующем; буфер не длиннее 2, лишние отбрасываются. Тесты: `GameStateTests.test_buffered_turns_apply_one_per_tick`, `test_buffer_cap_two` (Task 4).
3. Доска полностью заполнена после поедания последней клетки → game over без падения и без спавна еды. Тест: `BoardTests.test_board_full_is_draw_without_spawn` (Task 2).
4. Пауза длиннее секунды и возобновление → не «догоняет» пропущенные тики; enqueue во время паузы отбрасывается. Тест: `GameStateTests.test_enqueue_while_paused_is_dropped`; ручная проба в Task 6 (Step 5).
5. Resize окна на лету → меняется только размер клетки (`min(W, H−HUD)/25`), координаты доски не трогаются; минимум окна держит клетку ≥ 12 pt. Ручная проба: Task 7 Step 4.

---

### Task 1: Каркас проекта (SPM + git)

**Files:**
- Create: `Package.swift`, `.gitignore`
- Create: пустые заглушки `Sources/SnakeKit/Board.swift`, `Sources/SnakeApp/SnakeApp.swift` (по одному пустому комментарий-файлу на таргет, чтобы манифест собирался)

**Interfaces:**
- Produces: рабочий SPM-проект с тремя таргетами: библиотека `SnakeKit` (`Sources/SnakeKit/`), исполняемый `SnakeApp` (`Sources/SnakeApp/`, зависит от SnakeKit), тесты `SnakeKitTests` (`Tests/SnakeKitTests/`, зависят от SnakeKit). Все последующие задачи опираются на `swift build`, `swift test`, `swift run SnakeApp`.

- [ ] **Step 1: git init**

```bash
cd /Users/nikolay/hobby/snake && git init -b main && echo ".build/" > .gitignore
```

- [ ] **Step 2: Написать `Package.swift`**

```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Snake",
    platforms: [.macOS(.v14)],
    targets: [
        .library(name: "SnakeKit", path: "Sources/SnakeKit"),
        .executableTarget(name: "SnakeApp", dependencies: ["SnakeKit"], path: "Sources/SnakeApp"),
        .testTarget(name: "SnakeKitTests", dependencies: ["SnakeKit"], path: "Tests/SnakeKitTests")
    ]
)
```

Заглушки: `// SnakeKit placeholder` в `Sources/SnakeKit/Board.swift`, `// SnakeApp placeholder` в `Sources/SnakeApp/SnakeApp.swift`; каталог `Tests/SnakeKitTests/` создаётся пустым (SPM допускает тестовый таргет без файлов? — если сборка ругается, положите один файл с `import XCTest` и пустым `final class SmokeTest: XCTestCase { func testOk() {} }`; имя файла `SmokeTest.swift`).

- [ ] **Step 3: Проверить сборку**

Run: `swift build && swift test`
Expected: оба PASS. Если линковка исполняемого таргета падает на символах SwiftUI/AppKit (порожек SPM), добавьте в `.executableTarget`: `linkerSettings: [.linkedLibrary("SwiftUI"), .linkedLibrary("AppKit")]` — и повторите сборку.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "chore: scaffold SPM project (SnakeKit, SnakeApp, tests)"
```

---

### Task 2: `Board` — чистая сетевая логика

**Files:**
- Create/replace: `Sources/SnakeKit/Board.swift`
- Test: `Tests/SnakeKitTests/BoardTests.swift`

**Interfaces:**
- Produces (точные сигнатуры, используются всеми далее):

```swift
public struct Point: Hashable, Equatable { public let x: Int; public let y: Int }
public enum Direction { case up, down, left, right
    public var offset: SIMD2<Int>   // up=(0,-1), down=(0,+1), left=(-1,0), right=(+1,0)
}
public enum StepOutcome { case progressed, ateFood, hitWall, hitSelf, boardFull }

public struct Board {
    public let columns: Int; public let rows: Int
    public var snake: [Point]          // head — первый элемент
    public var direction: Direction
    public var food: Point
    /// Стандартная стартовая раскладка (25×25, змейка по центру вправо);
    /// первая еда спавнится системным RNG.
    public init(columns: Int = 25, rows: Int = 25)
    /// Тестовая полная раскладка — без RNG.
    public init(columns: Int, rows: Int, snake: [Point], direction: Direction, food: Point)
    public mutating func step<RNG: RandomNumberGenerator>(using rng: inout RNG) -> StepOutcome
}
```

- Consumes: ничего (корень дерева).

Алгоритм `step` — фиксированный порядок (реализатор не выбирает):
1. `newHead = head + direction.offset`; вне границ → `.hitWall`, без мутаций.
2. `ate = (newHead == food)`; тело для проверки: `ate ? snake : Array(snake.dropLast())` (хвост уходит, если не растём).
3. `newHead ∈ body` → `.hitSelf`, без мутаций.
4. Мутации: `snake.insert(newHead, at: 0)`; если `!ate` — `snake.removeLast()`.
5. Если `ate`: спавн новой еды в случайной свободной клетке (вне змейки) через `rng`; свободных нет → `.boardFull` (рост всё же применяется), иначе `.ateFood`. Иначе `.progressed`.

- [ ] **Step 1: Написать фейлинговые тесты** (`BoardTests.swift`)

В файле определите детерминированный RNG для тестов: `struct SplitMix64: RandomNumberGenerator` (стандартный splitmix64, конструктор принимает seed) — любой корректный генератор подойдёт.

Тесты с точными ассертами (сигнатуры + ключевые assert; тела дописываете):
- `test_step_moves_head_one_cell`: доска 5×5, snake `[(2,2),(1,2)]`, dir right, food `(4,0)` → после step head `(3,2)`, длина 2, `.progressed`.
- `test_hit_wall_no_mutation`: head `(4,2)`, dir right → `.hitWall`, snake/food не изменились.
- `test_hit_self`: snake `[(2,2),(2,1),(3,1),(3,2)]`... выберите раскладку 4 клетки так, что newHead попадает во вторую с конца+; assert `.hitSelf`.
- `test_move_into_vacating_tail_is_safe` (Review Focus #1): змейка в форме, где newHead = текущий хвост, без еды там → `.progressed`, длина не меняется.
- `test_eat_grows_and_spawns_off_snake`: snake 2 клетки, food прямо перед head; после step: length +1, result `.ateFood`, `board.food ∉ board.snake`.
- `test_spawn_invariant_500_ticks` (Review Focus #3 частично): доска 8×8, zмейка растёт 500 тиков SplitMix64(seed: 42); после каждого tick assert `board.food ∉ board.snake` и `step != .hitSelf/.hitWall`, пока игра жива.
- `test_board_full_is_draw_without_spawn` (Review Focus #3): доска 2×2, snake занимает 3 клетки, food в последней; один step → `.ateFood` НЕвозможен: после роста snake = все 4 клетки, следующий шаг невозможен — зафиксировать поведение: step при отсутствии свободных клеток для спавна возвращает `.boardFull` (см. алгоритм п.5). Ассертируйте `outcome == .boardFull`, `food не изменился(не заспавнился повторно)`.

- [ ] **Step 2: Убедиться, что тесты фейлят**

Run: `swift test --filter BoardTests`
Expected: компиляция падает (символы `Board`/`Point` не объявлены) или FAIL.

- [ ] **Step 3: Реализовать `Board.swift` по сигнатурам и алгоритму выше**

Выбор структуры данных фиксирован: `[Point]`, head-first; спавн еды — `Int.random(in: freeIndices, using: &rng)` по списку свободных клеток.

- [ ] **Step 4: Прогнать тесты до PASS**

Run: `swift test --filter BoardTests`
Expected: PASS все перечисленные.

- [ ] **Step 5: Commit**

```bash
git add Sources/SnakeKit/Board.swift Tests/SnakeKitTests/BoardTests.swift && git commit -m "feat: pure board logic (step, collisions, food spawn)"
```

---

### Task 3: `HighScoreStore` — рекорд в UserDefaults

**Files:**
- Create: `Sources/SnakeKit/HighScoreStore.swift`
- Test: `Tests/SnakeKitTests/HighScoreStoreTests.swift`

**Interfaces:**
- Produces:

```swift
public protocol HighScoreStore {
    func best() -> Int
    /// true, если score строго больше сохранённого рекорда (и тогда он записан).
    @discardableResult func submit(_ score: Int) -> Bool
}

public struct UserDefaultsHighScoreStore: HighScoreStore {
    public init(defaults: UserDefaults = .standard, key: String = "snake.best.score")
    // best(): Int из key или 0; submit(_:): compare-and-write
}
```

- [ ] **Step 1: Написать тесты**

- `test_fresh_store_best_is_zero`: `UserDefaultsHighScoreStore(defaults: UserDefaults(suiteName: #function)!)` → `best() == 0`.
- `test_submit_new_record_persists`: submit(7) → true; второй экземпляр с тем же suite и key → `best() == 7`; submit(3) → false, `best()` всё ещё 7.

- [ ] **Step 2: Прогнать до FAIL** (символы не объявлены)
Run: `swift test --filter HighScoreStoreTests` — Expected: ошибка компиляции/FAIL.

- [ ] **Step 3: Реализовать по сигнатурам**

`submit`: `let prev = best(); guard score > prev else { return false }; defaults.set(score, forKey: key); return true`.

- [ ] **Step 4: Прогнать до PASS**
Run: `swift test --filter HighScoreStoreTests` — Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SnakeKit/HighScoreStore.swift Tests/SnakeKitTests/HighScoreStoreTests.swift && git commit -m "feat: high score store (UserDefaults)"
```

---

### Task 4: `GameState` — движок состояния игры

**Files:**
- Create: `Sources/SnakeKit/GameState.swift`
- Test: `Tests/SnakeKitTests/GameStateTests.swift`

**Interfaces:**
- Consumes: `Board`, `StepOutcome` (Task 2); `HighScoreStore` (Task 3).
- Produces:

```swift
@MainActor @Observable
public final class GameState {
    public private(set) var board: Board
    public private(set) var score: Int          // начально 0
    public private(set) var best: Int           // из store на init
    public private(set) var isRunning: Bool     // true после startNewGame, false при game over
    public private(set) var isPaused: Bool
    public private(set) var isGameOver: Bool
    public private(set) var newRecord: Bool
    private var pendingTurns: [Direction]

    public init(store: HighScoreStore = UserDefaultsHighScoreStore(), columns: Int = 25, rows: Int = 25)
    // init сам вызывает startNewGame() — игра стартует сразу.

    public func startNewGame()   // сброс board/score/isPaused/isGameOver/newRecord; isRunning = true
    public func togglePause()    // no-op при game over или если не isRunning
    @discardableResult public func enqueueTurn(_ d: Direction) -> Bool
    /// Тестовый доступ к буферу (read-only).
    public var pendingTurnsView: [Direction] { get }
    public var ticksPerSecond: Double   // min(8 + score / 4, 15), целочисленное деление
    public func tick()                 // один тик; no-op при !isRunning || isGameOver
}
```

Правила (фиксированы):
- `enqueueTurn`: при `!isRunning || isPaused` → false. Игнор: `d == board.direction` или разворот 180° (`opposite(d) == board.direction`). Буфер ≤ 2; при переполнении выбрасывается старейший. Возвращает true, если принято.
- `tick()`: снять **не более одного** направления из буфера (применить к `board.direction`), затем `let out = board.step(using: &rng)` с внутренним `SystemRandomNumberGenerator`. `.ateFood` → `score += 1`. `.hitWall | .hitSelf | .boardFull` → `isGameOver = true; isRunning = false; newRecord = store.submit(score); best = max(best, score)`.
- `tick()` при `isPaused` **не вызывается циклом** (см. Task 5/6) — сам `tick` при паузе тоже no-op на всякий случай.

Тесты пишутся как `final class GameStateTests: XCTestCase` с меткой класса `@MainActor`, тест-методы `func test…() async throws`. Fake store для проверки рекорда определите в файле тестов:

```swift
final class FakeStore: HighScoreStore { var bestValue = 0; var submitted: [Int] = []
    func best() -> Int { bestValue }
    @discardableResult func submit(_ s: Int) -> Bool { if s > bestValue { bestValue = s }; submitted.append(s); return s > bestValue }
}
```

- [ ] **Step 1: Написать тесты** (ключевые ассерты):
- `test_initial_layout`: после init — `board.snake == [Point(x:12,y:12), Point(x:11,y:12), Point(x:10,y:12)]`, `direction == .right`, `score == 0`, `isRunning && !isPaused && !isGameOver`.
- `test_enqueue_reverse_ignored`: `enqueueTurn(.left) == false` (старт вправо).
- `test_buffered_turns_apply_one_per_tick` (Review Focus #2): `enqueueTurn(.up); enqueueTurn(.left)`; `tick()` → `direction == .up`; ещё `tick()` → `.left`; буфер пуст.
- `test_buffer_cap_two`: три разных поворота подряд → в `pendingTurnsView` ровно 2 (старейший выброшен).
- `test_enqueue_while_paused_is_dropped` (Review Focus #4): pause, enqueue(.up) == false, unpause — направление не изменилось.
- `test_speed_formula`: score 0/3 → 8.0; score 4 → 9.0; score 28 и 100 → 15.0 (потолок).
- `test_death_submits_record_and_freezes`: на небольшой тестовой доске загоните змейку в стену (через full init Board — для этого добавьте в GameState тестовый путь: создавайте `GameState` с fake store и подгоняйте поле через несколько `enqueueTurn`/`tick`, либо расширьте init тестовым параметром `board:` — допустимый выбор реализатора, но фиксировать не обязательно); assert `isGameOver == true`, `store.submitted.last == score`, повторный `tick()` ничего не меняет.
- `test_restart_resets`: после game over — `startNewGame()` → score 0, `newRecord == false`, `isRunning == true`, стартовая раскладка заново; `best` сохранён (в FakeStore: bestValue не сбрасывается).

- [ ] **Step 2: Прогнать до FAIL**
Run: `swift test --filter GameStateTests` — Expected: ошибка компиляции/FAIL.

- [ ] **Step 3: Реализовать `GameState.swift` по сигнатурам и правилам выше**

RNG хранить как `private let rng = SystemRandomNumberGenerator()`.

- [ ] **Step 4: Прогнать до PASS**
Run: `swift test --filter GameStateTests` — Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SnakeKit/GameState.swift Tests/SnakeKitTests/GameStateTests.swift && git commit -m "feat: game state engine (turns, speed, death, record)"
```

---

### Task 5: `InputMapping` + оболочка приложения с игровым циклом

**Files:**
- Create: `Sources/SnakeKit/InputMapping.swift`
- Test: `Tests/SnakeKitTests/InputMappingTests.swift`
- Replace: `Sources/SnakeApp/SnakeApp.swift` (заглушка)
- Create: `Sources/SnakeApp/GameView.swift`, `Sources/SnakeApp/GameClock.swift`

**Interfaces:**
- Consumes: `GameState` (Task 4).
- Produces:

```swift
public enum InputMapping {   // Sources/SnakeKit/InputMapping.swift
    /// стрелки + WASD → Direction; всё остальное — nil.
    public static func direction(forKeyCode code: Int) -> Direction?
    public static let pauseKeyCode = 49      // space
    public static let restartKeyCode = 36   // return (и space тоже рестартует при game over)
}
```
```swift
@MainActor final class GameClock {          // Sources/SnakeApp/GameClock.swift
    private var task: Task<Void, Never>?
    public func start(state: GameState)     // stop() затем новый цикл
    public func stop()
}
```
Цикл (фиксированная семантика): `task = Task { while state.isRunning && !state.isGameOver { try? await Task.sleep(for: .seconds(1.0 / state.ticksPerSecond)); if !state.isPaused { state.tick() } } }`. Пауза не останавливает задачу — тики просто пропускаются; задача завершается сама при game over. `start` сначала вызывает `stop()` (на случай рестарта).

- [ ] **Step 1: Тесты `InputMappingTests`**

- `test_arrows`: codes 123/124/125/126 → `.left/.right/.down/.up`.
- `test_wasd`: 0→.left, 17→.up, 1→.down, 2→.right.
- `test_unmapped_returns_nil`: 49, 36 и любой другой (например 5) → nil.

Run до FAIL: `swift test --filter InputMappingTests` — Expected: ошибка компиляции/FAIL.

- [ ] **Step 2: Реализовать `InputMapping.swift`**

Словарь ключевых кодов: `[123,0]: .left, [124,2]: .right, [125,1]: .down, [126,17]: .up`, остальное nil.

Run: `swift test --filter InputMappingTests` — Expected: PASS.

- [ ] **Step 3: Написать оболочку приложения**

`GameClock.swift` по семантике выше. `SnakeApp.swift`:
- `@main struct SnakeApp: App`, один `WindowGroup { GameView(state:) }`; состояние — `let state = GameState()` на уровне App (создаётся один раз).
- При старте процесса: `NSApp.setActivationPolicy(.regular)` и активация окна (обычный исполняемый файл SPM стартует с background-политикой) — например, в `.onAppear` GameView: `NSApp.activate(ignoringOtherApps: true)`.
- Окно: default content size 720×780; min content 356×412 (клетка ≥ ~12 pt).

`GameView.swift` (заготовка, без HUD/оверлеев — их делает Task 7): `@State var clock = GameClock()`; `.onAppear { clock.start(state) }`; `.onDisappear { clock.stop() }`; `Canvas` рисует: фон доски, змейку прямоугольниками (head — темнее), еду кругом. Размер клетки: `let s = min(size.width, size.height - 40) / CGFloat(board.columns)`; отрисовка по `state.board.snake`, координаты `Point(x,y)` → пиксели `(x*s, hud + y*s)`, `hud = 40`.

- [ ] **Step 4: Проверить ручной прогон**

Run: `swift run SnakeApp`
Expected: открывается окно; змейка сама едет вправо (~8 тик/с), доезжает до стены — игра останавливается (game over), без падения процесса.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: app shell, input mapping, game loop"
```

---

### Task 6: Управление с клавиатуры (NSEvent-монитор)

**Files:**
- Modify: `Sources/SnakeApp/GameView.swift` (добавить монитор клавиш; остальное не трогать)

**Interfaces:**
- Consumes: `InputMapping` (Task 5), `GameState.enqueueTurn/togglePause/startNewGame` (Task 4), `GameClock.start` (Task 5).

Правила ввода (фиксированы):
- Монитор: `NSEvent.addLocalMonitorForEvents(matching: .keyDown)`, сохранить возвращаемый объект в `@State var monitor: Any?`; `.onDisappear` — `monitor?.removeMonitor... ` нет: `NSEvent.removeMonitor(monitor!)`. (Ссылка живёт, пока окно живо.)
- Обработчик при game over: только restartKeyCode (36) или space (49) → `state.startNewGame(); clock.start(state)`; ключ «съедается» (`return nil`), чтобы не было системного бипа.
- В игре: `InputMapping.direction(forKeyCode:) != nil` → `state.enqueueTurn(d)` и `return nil`; space → `state.togglePause()` и `return nil`; все остальные коды → вернуть событие как есть (не глотать).

- [ ] **Step 1: Реализовать монитор в GameView по правилам выше**

Код определяет правила; реализатор пишет связку с существующими полями.

- [ ] **Step 2: Ручная проба управления**

Run: `swift run SnakeApp`
Expected: стрелки/WASD меняют направление без разворота на 180° (тап «влево» при движении вправо игнорируется); быстрая пара «вверх→влево» гасится буфером; space ставит паузу и снимает её; после game over Enter или space рестартует игру заново.

- [ ] **Step 3: Ручная проба Review Focus #4 (пауза)**

Run: `swift run SnakeApp` → паузa на ~10 s → снять паузу. Expected: змейка не «телепортируется» и не догоняет; скорость прежняя; тапы во время паузы направление не меняют.

- [ ] **Step 4: Commit**

```bash
git add Sources/SnakeApp/GameView.swift && git commit -m "feat: keyboard controls (NSEvent monitor)"
```

---

### Task 7: HUD, отрисовка, оверлеи

**Files:**
- Modify: `Sources/SnakeApp/GameView.swift` (HUD-полоса, цвета, сетка, оверлеи)

**Interfaces:**
- Consumes: только `GameState` (score/best/isPaused/isGameOver/newRecord) — новых сигнатур нет.

Визуальные решения (мои вызовы из дизайна):
- HUD сверху, высота 40 pt: слева «Score: N», справа «Best: M» (`monospacedDigit`, ~15 pt).
- Фон доски: `Color(white: 0.97)`; сетка — линии opacity 0.06 (только когда клетка ≥ 8 pt, иначе не рисовать);
- Змейка: rounded rect радиусом ~30% клетки, тело `Color(red: 0.35, green: 0.78, blue: 0.40)`, head `Color(red: 0.0, green: 0.55, blue: 0.20)`;
- Еда: красный круг радиусом ~36% клетки.
- Оверлей «Paused» по центру при `isPaused`: текст «Paused — Space to resume».
- Оверлей game over: полупрозрачная панель по центру: «Game over», «Score: N», если `newRecord` — строка «New best!», подсказка «Enter to restart».

- [ ] **Step 1: Реализовать HUD и оверлеи в GameView по спецификации выше**

Оверлеи рисуются поверх Canvas (ZStack), не мешая монитору клавиш из Task 6.

- [ ] **Step 2: Ручной прогон**

Run: `swift run SnakeApp`; дождаться game over. Expected: HUD обновляет счёт; при паузе виден оверлей; на game over — панель со счётом, «New best!» появляется только при новом рекорде.

- [ ] **Step 3: Проверить стартовый рекорд**

Убедиться (через `defaults read -app Snake` или прямой запуск второго раза) что после игры с счётом > 0 в HUD «Best» показывает сохранённое значение после перезапуска (`swift run SnakeApp` повторно).

- [ ] **Step 4: Ручная проба Review Focus #5 (resize)**

Run: `swift run SnakeApp`; во время игры растянуть/сжать окно. Expected: змейка не «прыгает» в логических координатах (только пересчёт размера клетки); при минимальном окне клетка остаётся ≥ 12 pt, HUD на месте.

- [ ] **Step 5: Commit**

```bash
git add Sources/SnakeApp/GameView.swift && git commit -m "feat: HUD, colors, pause/game-over overlays"
```

---

### Task 8: Сборка `.app` + финальная E2E-проверка

**Files:**
- Create: `scripts/make-app.sh` (сборка release + сборка бандла)
- Create: `Snake.app/Contents/Info.plist` (генерируется скриптом)

**Interfaces:**
- Consumes: всё предыдущее. Deliverable — локальный запускаемый бандл.

Скрипт делает ровно это:
1. `swift build -c release`
2. Создать каталог `Snake.app/Contents/{MacOS,Resources}`; скопировать `.build/release/SnakeApp` → `Snake.app/Contents/MacOS/Snake`.
3. Записать `Info.plist`: CFBundleName=Snake, CFBundleExecutable=Snake, CFBundleIdentifier=com.hobby.snake, CFBundlePackageType=APPL, CFBundleShortVersionString=1.0, LSMinimumSystemVersion=14.0, NSHighResolutionCapable=true.
4. `codesign --force --sign - Snake.app` (ad-hoc; только для локального запуска).

- [ ] **Step 1: Написать и запустить скрипт**

Run: `bash scripts/make-app.sh`
Expected: собирается без ошибок; существует `Snake.app/Contents/MacOS/Snake`.

- [ ] **Step 2: E2E-проверка полного сценария (ручная)**

Run: `open Snake.app`
Expected, за один сеанс: стартовое движение → управление работает → пауза/возобновление → рост и счёт растут → game over по стене или себе → «New best!» при новом рекорде → Enter рестартует. Закрыть приложение; запустить повторно → HUD «Best» показывает предыдущий рекорд.

- [ ] **Step 3: Финальный commit**

```bash
git add -A && git commit -m "feat: package Snake.app + E2E verified"
```

---

## Self-review (выполнено автором плана)

1. **Покрытие спеки:** движение/еда/рост/столкновения → Tasks 2,4; ускорение → Task 4 (`ticksPerSecond` + тесты); пауза/рестарт → Tasks 4,6; рекорд в UserDefaults и «new record» → Tasks 3,7,8; NSEvent-монитор ввода (вызов дизайна) → Task 5–6. Не-цели (звуки, уровни, геймпад) — задач нет намеренно.
2. **Шаги:** каждый шаг = одно действие с проверяемым результатом; тела кода не транскрибируются сверх фиксированных сигнатур/алгоритма `Board.step` и семантики цикла (оба места — единственные, где тесты+сигнатуры не определяют реализацию).
3. **Согласованность типов:** `Point/Direction/StepOutcome/Board/HighScoreStore/GameState/InputMapping/GameClock` определены один раз (Tasks 2–5) и используются в Tasks 4–8 только этими именами.
4. **Review Focus:** все пять строк закреплены тестами (Tasks 2,4) или ручными пробами (Tasks 6,7).
5. **Пропорция:** план ≈ вдвое длиннее спеки — соответствует размеру проекта (8 задач с TDD-циклами), транскриптом программы не является.
