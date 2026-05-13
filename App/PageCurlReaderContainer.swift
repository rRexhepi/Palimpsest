#if os(iOS)
import SwiftUI
import UIKit

/// SwiftUI wrapper around `UIPageViewController(transitionStyle: .pageCurl)`
/// — the same page-curl Apple's Books app uses. Replaces the custom
/// SwiftUI dog-ear on iOS so we get gesture-driven page lifting, the
/// peek-the-next-page-when-you-lift-the-corner behavior, swipe-velocity-
/// aware completion, and a proper cylindrical curl that ends at the page
/// edge instead of a half-spread overlay.
///
/// Pages are addressed by a flat 0..<totalPages index that the parent is
/// responsible for mapping to (chapter, pageInChapter). Each page is built
/// on demand by `pageBuilder(globalIndex)`. The coordinator updates
/// `currentIndex` whenever the user lands on a new page so the parent's
/// SwiftData progress + chapter-list selection stays in sync.
struct PageCurlReaderContainer: UIViewControllerRepresentable {
    let totalPages: Int
    @Binding var currentIndex: Int
    /// `true` for iPad landscape — show two pages side-by-side and curl one
    /// at a time, like Books.app. `false` for iPhone and iPad portrait —
    /// single-page curl. Switching this value rebuilds the container (the
    /// caller should change the SwiftUI `.id` so a new instance is built).
    let useSpread: Bool
    let pageBuilder: (Int) -> AnyView
    /// Filled by the container so SwiftUI parents can request an animated
    /// page flip (i.e. with the curl animation, not a snap). Tap-to-flip
    /// zones call this; chapter picks / progress restoration go through
    /// `currentIndex` directly and snap.
    @Binding var flipController: ((Bool) -> Void)?

    func makeUIViewController(context: Context) -> UIPageViewController {
        // `.mid` spine asks the PVC to display two view controllers side
        // by side and curl the one the user grabs. Default `.min` is the
        // single-page curl.
        let options: [UIPageViewController.OptionsKey: Any] = useSpread
            ? [.spineLocation: NSNumber(value: UIPageViewController.SpineLocation.mid.rawValue)]
            : [:]
        let pvc = UIPageViewController(
            transitionStyle: .pageCurl,
            navigationOrientation: .horizontal,
            options: options
        )
        pvc.dataSource = context.coordinator
        pvc.delegate = context.coordinator
        // The back of the curling page in `.pageCurl` mode shows the
        // PVC view's own background (and the child hosting view's, since
        // the hosting view sits inside it). Default `.systemBackground`
        // is white in light mode and reads as a stark sheet of paper
        // flipping over the parchment. Match the canvas color so the
        // curl reads as a single uniform leaf.
        pvc.view.backgroundColor = Self.parchmentCanvasUIColor
        pvc.view.isOpaque = true
        if totalPages > 0 {
            setControllers(on: pvc, animated: false, direction: .forward)
        }
        // Hand the coordinator's flip helper back to SwiftUI so taps can
        // drive an animated flip without going through the binding (the
        // binding path is reserved for instant snaps).
        DispatchQueue.main.async { [weak coord = context.coordinator] in
            flipController = { forward in coord?.flipPage(forward: forward) }
        }
        return pvc
    }

    /// Same parchment as `Theme.canvas`, expressed as a trait-aware UIColor
    /// so it follows light / dark mode automatically. Kept in sync with
    /// `Theme.swift`'s canvas tokens.
    static let parchmentCanvasUIColor = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red:  27/255, green:  24/255, blue:  21/255, alpha: 1)
            : UIColor(red: 244/255, green: 239/255, blue: 230/255, alpha: 1)
    }

    func updateUIViewController(_ pvc: UIPageViewController, context: Context) {
        // Sync external currentIndex changes. The `animated` flag here
        // determines whether the page transition uses the curl animation
        // (e.g. when the user taps left/right to flip) or jumps instantly
        // (e.g. picking a chapter from the drawer). The coordinator tracks
        // the most recent intent.
        guard totalPages > 0 else { return }
        let safe = max(0, min(currentIndex, totalPages - 1))
        let visible = pvc.viewControllers?.compactMap { ($0 as? IndexedHostingController)?.pageIndex } ?? []
        let animated = context.coordinator.consumeAnimatedFlip()
        if useSpread {
            // In spread mode the visible pair is [left, right] = [N, N+1].
            // The "current" position is normalised to the LEFT (even).
            let leftIdx = (safe / 2) * 2
            if visible.first == leftIdx { return }
            let direction: UIPageViewController.NavigationDirection =
                leftIdx > (visible.first ?? 0) ? .forward : .reverse
            setControllers(on: pvc, animated: animated, direction: direction, override: leftIdx)
        } else {
            guard let firstShown = visible.first, firstShown != safe else { return }
            let direction: UIPageViewController.NavigationDirection =
                safe > firstShown ? .forward : .reverse
            pvc.setViewControllers([makePage(at: safe)], direction: direction, animated: animated)
        }
    }

    /// Build the visible-controller set from the current `currentIndex`.
    /// Single-page = one VC; spread = a pair (left + right), or just the
    /// left/right alone at the spine ends.
    private func setControllers(
        on pvc: UIPageViewController,
        animated: Bool,
        direction: UIPageViewController.NavigationDirection,
        override: Int? = nil
    ) {
        let safe = max(0, min(override ?? currentIndex, totalPages - 1))
        if useSpread {
            let leftIdx = (safe / 2) * 2
            let leftVC = makePage(at: leftIdx)
            if leftIdx + 1 < totalPages {
                let rightVC = makePage(at: leftIdx + 1)
                pvc.setViewControllers([leftVC, rightVC], direction: direction, animated: animated)
            } else {
                pvc.setViewControllers([leftVC], direction: direction, animated: animated)
            }
        } else {
            pvc.setViewControllers([makePage(at: safe)], direction: direction, animated: animated)
        }
    }

    private func makePage(at index: Int) -> IndexedHostingController {
        IndexedHostingController(pageIndex: index, rootView: pageBuilder(index))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        let parent: PageCurlReaderContainer
        /// Set true from `flipPage(...)` so the very next `updateUIView-
        /// Controller` honours the curl animation. Cleared after the read
        /// so unrelated index changes (chapter picks, restoreProgress)
        /// still snap instantly.
        private var pendingAnimatedFlip = false

        init(parent: PageCurlReaderContainer) {
            self.parent = parent
        }

        func flipPage(forward: Bool) {
            let target = forward ? parent.currentIndex + 1 : parent.currentIndex - 1
            guard target >= 0, target < parent.totalPages else { return }
            pendingAnimatedFlip = true
            parent.currentIndex = target
        }

        func consumeAnimatedFlip() -> Bool {
            let v = pendingAnimatedFlip
            pendingAnimatedFlip = false
            return v
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerBefore viewController: UIViewController
        ) -> UIViewController? {
            guard let current = viewController as? IndexedHostingController,
                  current.pageIndex > 0 else { return nil }
            let prev = current.pageIndex - 1
            return IndexedHostingController(pageIndex: prev, rootView: parent.pageBuilder(prev))
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerAfter viewController: UIViewController
        ) -> UIViewController? {
            guard let current = viewController as? IndexedHostingController,
                  current.pageIndex < parent.totalPages - 1 else { return nil }
            let next = current.pageIndex + 1
            return IndexedHostingController(pageIndex: next, rootView: parent.pageBuilder(next))
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            didFinishAnimating finished: Bool,
            previousViewControllers: [UIViewController],
            transitionCompleted completed: Bool
        ) {
            guard finished, completed,
                  let current = pageViewController.viewControllers?.first as? IndexedHostingController
            else { return }
            // Bounce back to the binding on the next runloop so SwiftUI's
            // diffing picks it up cleanly without re-entering the
            // updateUIViewController path mid-animation.
            DispatchQueue.main.async {
                self.parent.currentIndex = current.pageIndex
            }
        }
    }
}

/// `UIHostingController` subclass that remembers which page it represents.
/// `UIPageViewController` calls `viewControllerBefore/After` with the
/// existing instance and we read this back to know our position in the
/// flat page sequence.
final class IndexedHostingController: UIHostingController<AnyView> {
    let pageIndex: Int

    init(pageIndex: Int, rootView: AnyView) {
        self.pageIndex = pageIndex
        super.init(rootView: rootView)
        view.backgroundColor = PageCurlReaderContainer.parchmentCanvasUIColor
        // The back of the curling page in UIPageViewController.pageCurl is
        // a translucent UIKit layer that lets the view *below* show through.
        // Marking the hosting view fully opaque + giving it a solid
        // parchment fill means the curl back reads as a real sheet of
        // paper instead of frosted glass.
        view.isOpaque = true
        view.layer.isOpaque = true
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
#endif
