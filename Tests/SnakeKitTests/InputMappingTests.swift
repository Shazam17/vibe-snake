import XCTest
import SnakeKit

final class InputMappingTests: XCTestCase {

    func test_arrows() {
        XCTAssertEqual(InputMapping.direction(forKeyCode: 123), Direction.left)
        XCTAssertEqual(InputMapping.direction(forKeyCode: 124), Direction.right)
        XCTAssertEqual(InputMapping.direction(forKeyCode: 125), Direction.down)
        XCTAssertEqual(InputMapping.direction(forKeyCode: 126), Direction.up)
    }

    func test_wasd() {
        XCTAssertEqual(InputMapping.direction(forKeyCode: 0), Direction.left)
        XCTAssertEqual(InputMapping.direction(forKeyCode: 17), Direction.up)
        XCTAssertEqual(InputMapping.direction(forKeyCode: 1), Direction.down)
        XCTAssertEqual(InputMapping.direction(forKeyCode: 2), Direction.right)
    }

    func test_unmapped_returns_nil() {
        XCTAssertNil(InputMapping.direction(forKeyCode: 49))
        XCTAssertNil(InputMapping.direction(forKeyCode: 36))
        XCTAssertNil(InputMapping.direction(forKeyCode: 5))
    }
}
