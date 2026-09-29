import AppKit
import CoreGraphics
import Defaults

/// Detects Windows 11 style snap groups: two on-screen windows that together fill one screen,
/// one on the left half and one on the right half.
///
/// Membership is inferred purely from geometry, so it works with macOS tiling, Rectangle,
/// Snap Assist or manual placement, and a group dissolves as soon as either window moves away.
/// A group is shown as one synthetic `WindowInfo` entry whose preview is both windows side by
/// side and whose activation brings both windows to the front.
enum SnapGroups {
    /// The minimal window facts needed to detect groups, kept free of AppKit types so the
    /// pairing logic stays pure and unit-testable.
    struct Candidate {
        let id: CGWindowID
        let pid: pid_t
        /// CG coordinates (origin top-left).
        let frame: CGRect
    }

    struct Member: Hashable {
        let id: CGWindowID
        let pid: pid_t
    }

    struct Pair: Hashable {
        let left: Member
        let right: Member

        func contains(_ id: CGWindowID) -> Bool {
            left.id == id || right.id == id
        }
    }

    /// Same slack as Snap Assist so both agree on what counts as "exactly one half".
    static let tolerance: CGFloat = 12

    /// Pairs the frontmost left-half window with the frontmost right-half window of every screen.
    /// `candidates` must be in z-order (front first); `screens` are visible frames in CG coordinates.
    static func pairs(in candidates: [Candidate], screens: [CGRect]) -> [Pair] {
        var pairs: [Pair] = []
        var used = Set<CGWindowID>()

        for screen in screens {
            let halfWidth = (screen.width / 2).rounded(.down)
            let leftHalf = CGRect(x: screen.minX, y: screen.minY, width: halfWidth, height: screen.height)
            let rightHalf = CGRect(x: screen.minX + halfWidth, y: screen.minY, width: screen.width - halfWidth, height: screen.height)

            guard let left = candidates.first(where: { !used.contains($0.id) && matches($0.frame, leftHalf) }),
                  let right = candidates.first(where: { !used.contains($0.id) && $0.id != left.id && matches($0.frame, rightHalf) })
            else { continue }

            used.insert(left.id)
            used.insert(right.id)
            pairs.append(Pair(left: Member(id: left.id, pid: left.pid), right: Member(id: right.id, pid: right.pid)))
        }

        return pairs
    }

    static func matches(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }

    /// Stable ID for a group entry so merges keep it in place; the top bit keeps it clear of real CGWindowIDs.
    static func syntheticID(left: CGWindowID, right: CGWindowID) -> CGWindowID {
        0x8000_0000 | ((left & 0x7FFF) << 15) | (right & 0x7FFF)
    }

    static func title(left: WindowInfo, right: WindowInfo) -> String {
        let leftApp = left.app.localizedName ?? ""
        let rightApp = right.app.localizedName ?? ""
        if leftApp == rightApp, let l = left.windowName, let r = right.windowName, !l.isEmpty, !r.isEmpty {
            return "\(l) + \(r)"
        }
        return "\(leftApp) + \(rightApp)"
    }

    // MARK: - Live detection

    /// Current pairs, read from the on-screen window list so frames are never stale.
    static func currentPairs() -> [Pair] {
        let ownPid = ProcessInfo.processInfo.processIdentifier
        let list = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []

        let candidates: [Candidate] = list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  pid != ownPid,
                  ((info[kCGWindowAlpha as String] as? Double) ?? 1) > 0.05,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.width > 0, bounds.height > 0
            else { return nil }
            return Candidate(id: id, pid: pid, frame: bounds)
        }

        guard !candidates.isEmpty else { return [] }
        return pairs(in: candidates, screens: NSScreen.screens.map(cgVisibleFrame))
    }

    /// Visible frame (without menu bar and Dock) in CG coordinates.
    static func cgVisibleFrame(_ screen: NSScreen) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let visible = screen.visibleFrame
        return CGRect(x: visible.minX, y: primaryHeight - visible.maxY, width: visible.width, height: visible.height)
    }

    // MARK: - Group entries

    /// Appends one synthetic group entry for every snap pair that includes at least one of `windows`.
    /// A partner that belongs to another app is resolved from the window cache.
    static func appendingGroupEntries(to windows: [WindowInfo]) -> [WindowInfo] {
        guard Defaults[.showSnapGroups], !windows.isEmpty else { return windows }
        let pairs = currentPairs()
        guard !pairs.isEmpty else { return windows }

        var byID: [CGWindowID: WindowInfo] = [:]
        for window in windows where !window.isSnapGroup && !window.isWindowlessApp {
            byID[window.id] = window
        }

        var result = windows.filter { !$0.isSnapGroup }
        for pair in pairs {
            let localLeft = byID[pair.left.id]
            let localRight = byID[pair.right.id]
            guard let primary = localLeft ?? localRight,
                  let left = localLeft ?? cachedWindow(pair.left),
                  let right = localRight ?? cachedWindow(pair.right)
            else { continue }
            result.append(WindowInfo.snapGroupEntry(left: left, right: right, primary: primary))
        }
        return result
    }

    private static func cachedWindow(_ member: Member) -> WindowInfo? {
        WindowUtil.readCachedWindows(for: member.pid).first {
            $0.id == member.id && !$0.isMinimized && !$0.isHidden
        }
    }

    // MARK: - Composite preview image

    private struct CompositeKey: Hashable {
        let left: CGWindowID
        let right: CGWindowID
        let leftCaptured: Date
        let rightCaptured: Date
    }

    private static var compositeCache: [CompositeKey: CGImage] = [:]
    private static let compositeLock = NSLock()
    private static let maxCompositeHeight = 900

    static func compositeImage(for left: WindowInfo, right: WindowInfo) -> CGImage? {
        let key = CompositeKey(left: left.id, right: right.id, leftCaptured: left.imageCapturedTime, rightCaptured: right.imageCapturedTime)

        compositeLock.lock()
        if let cached = compositeCache[key] {
            compositeLock.unlock()
            return cached
        }
        compositeLock.unlock()

        guard let image = compositeImage(left: left.image, right: right.image) else { return nil }

        compositeLock.lock()
        if compositeCache.count > 16 {
            compositeCache.removeAll()
        }
        compositeCache[key] = image
        compositeLock.unlock()
        return image
    }

    /// Both thumbnails side by side at a shared height with a small transparent gap.
    /// A missing thumbnail is drawn as a neutral placeholder shaped like half a screen.
    static func compositeImage(left: CGImage?, right: CGImage?) -> CGImage? {
        guard left != nil || right != nil else { return nil }
        let height = min(max(left?.height ?? 0, right?.height ?? 0), maxCompositeHeight)
        guard height > 0 else { return nil }

        func scaledWidth(_ image: CGImage?) -> Int {
            guard let image, image.height > 0 else { return height * 4 / 5 }
            return max(1, Int(CGFloat(image.width) * CGFloat(height) / CGFloat(image.height)))
        }

        let leftWidth = scaledWidth(left)
        let rightWidth = scaledWidth(right)
        let gap = max(4, height / 60)
        let width = leftWidth + gap + rightWidth

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high

        func draw(_ image: CGImage?, in rect: CGRect) {
            if let image {
                context.draw(image, in: rect)
            } else {
                context.setFillColor(CGColor(gray: 0.5, alpha: 0.35))
                context.fill(rect)
            }
        }

        draw(left, in: CGRect(x: 0, y: 0, width: leftWidth, height: height))
        draw(right, in: CGRect(x: leftWidth + gap, y: 0, width: rightWidth, height: height))
        return context.makeImage()
    }
}
