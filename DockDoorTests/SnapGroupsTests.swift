import CoreGraphics
@testable import DockDoor
import Foundation
import Testing

// MARK: - SnapGroups Tests

struct SnapGroupsTests {
    // 1512x982 display, menu bar 25 px, no Dock in the way.
    private let screen = CGRect(x: 0, y: 25, width: 1512, height: 957)
    private var leftHalf: CGRect { CGRect(x: 0, y: 25, width: 756, height: 957) }
    private var rightHalf: CGRect { CGRect(x: 756, y: 25, width: 756, height: 957) }

    private func candidate(_ id: CGWindowID, pid: pid_t = 100, _ frame: CGRect) -> SnapGroups.Candidate {
        SnapGroups.Candidate(id: id, pid: pid, frame: frame)
    }

    @Test func pairsLeftAndRightHalf() {
        let pairs = SnapGroups.pairs(in: [
            candidate(1, pid: 100, leftHalf),
            candidate(2, pid: 200, rightHalf),
        ], screens: [screen])

        #expect(pairs == [SnapGroups.Pair(left: .init(id: 1, pid: 100), right: .init(id: 2, pid: 200))])
    }

    @Test func toleratesSmallDeviations() {
        let slightlyOff = leftHalf.offsetBy(dx: 5, dy: -4).insetBy(dx: 3, dy: 3)
        let pairs = SnapGroups.pairs(in: [
            candidate(1, slightlyOff),
            candidate(2, rightHalf),
        ], screens: [screen])

        #expect(pairs.count == 1)
    }

    @Test func rejectsWindowsOutsideTolerance() {
        let tooNarrow = CGRect(x: 0, y: 25, width: 700, height: 957)
        let pairs = SnapGroups.pairs(in: [
            candidate(1, tooNarrow),
            candidate(2, rightHalf),
        ], screens: [screen])

        #expect(pairs.isEmpty)
    }

    @Test func needsBothHalves() {
        let pairs = SnapGroups.pairs(in: [
            candidate(1, leftHalf),
            candidate(2, CGRect(x: 800, y: 100, width: 600, height: 500)),
        ], screens: [screen])

        #expect(pairs.isEmpty)
    }

    @Test func picksFrontmostWindowPerHalf() {
        let pairs = SnapGroups.pairs(in: [
            candidate(10, leftHalf),
            candidate(11, leftHalf),
            candidate(20, rightHalf),
            candidate(21, rightHalf),
        ], screens: [screen])

        #expect(pairs.map(\.left.id) == [10])
        #expect(pairs.map(\.right.id) == [20])
    }

    @Test func pairsPerScreen() {
        let second = CGRect(x: 1512, y: 0, width: 1920, height: 1080)
        let pairs = SnapGroups.pairs(in: [
            candidate(1, leftHalf),
            candidate(2, rightHalf),
            candidate(3, CGRect(x: 1512, y: 0, width: 960, height: 1080)),
            candidate(4, CGRect(x: 2472, y: 0, width: 960, height: 1080)),
        ], screens: [screen, second])

        #expect(pairs.count == 2)
        #expect(pairs[1].left.id == 3)
        #expect(pairs[1].right.id == 4)
    }

    @Test func syntheticIDIsStableAndFlagged() {
        let a = SnapGroups.syntheticID(left: 12, right: 34)
        let b = SnapGroups.syntheticID(left: 12, right: 34)
        let swapped = SnapGroups.syntheticID(left: 34, right: 12)

        #expect(a == b)
        #expect(a != swapped)
        #expect(a & 0x8000_0000 != 0)
    }
}
