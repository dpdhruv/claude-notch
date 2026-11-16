import XCTest
@testable import NotchCore

final class ScreenPickerTests: XCTestCase {
    private let laptop = ScreenPicker.Screen(id: 0, hasNotch: true, isMain: false)
    private let external = ScreenPicker.Screen(id: 1, hasNotch: false, isMain: true)

    func testPrefersTheScreenWithTheNotchWhenTheLidIsOpen() {
        XCTAssertEqual(ScreenPicker.pick(from: [external, laptop]), laptop)
    }

    func testFallsBackToTheMainDisplayWhenTheLidIsClosed() {
        XCTAssertEqual(ScreenPicker.pick(from: [external]), external)
    }

    func testWithoutAMainFlagTheFirstScreenIsUsed() {
        let other = ScreenPicker.Screen(id: 2, hasNotch: false, isMain: false)
        XCTAssertEqual(ScreenPicker.pick(from: [other, ScreenPicker.Screen(id: 3, hasNotch: false, isMain: false)]), other)
        XCTAssertNil(ScreenPicker.pick(from: []))
    }
}
