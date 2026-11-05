import SwiftUI
import UIKit

// Whether the photo is being pinched or dragged (or just was). A finger lifting at the end of a pinch
// over a dish line would otherwise count as a tap on that dish.
final class ZoomActivity {
    var busyUntil = Date.distantPast
    var isBusy: Bool { Date() < busyUntil }
}

// The menu photo behind everything, which you can pinch to zoom and drag in any direction, like a map.
// It starts filling the whole screen, under the floating bars, and zooms out until the whole photo
// shows. The SwiftUI content inside keeps its taps.
struct ZoomView<Content: View>: UIViewRepresentable {
    var aspect: CGFloat             // the content's height divided by its width
    var insets: EdgeInsets          // bars drawn over the photo
    var focus: CGRect? = nil        // a part to bring into view, 0 to 1 of the content
    var bottomCover: CGFloat = 0    // more of the bottom hidden, such as by a sheet
    var activity: ZoomActivity? = nil
    // The content is laid out this many times larger and shown scaled down, so text drawn in it
    // stays sharp when zoomed in (zooming only stretches what was drawn).
    var detail: CGFloat = 1
    // A single tap, at a point in the content (unzoomed), with the content's size.
    // Taps are found here rather than by buttons inside, so a pinch that starts on a line still zooms.
    var onTap: ((CGPoint, CGSize) -> Void)? = nil
    @ViewBuilder var content: () -> Content

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.delegate = context.coordinator
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.backgroundColor = .clear
        // No frosted band under the bars: the controls float right on the photo.
        scroll.topEdgeEffect.isHidden = true
        scroll.bottomEdgeEffect.isHidden = true

        let host = UIHostingController(rootView: AnyView(content()))
        host.view.backgroundColor = .clear
        host.safeAreaRegions = []
        scroll.addSubview(host.view)
        context.coordinator.host = host

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        scroll.addGestureRecognizer(tap)
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.host?.rootView = AnyView(content())
        coordinator.insets = UIEdgeInsets(top: insets.top, left: insets.leading, bottom: insets.bottom, right: insets.trailing)
        coordinator.aspect = aspect
        coordinator.activity = activity
        coordinator.onTap = onTap
        coordinator.detail = max(1, detail)
        coordinator.layout(scroll)
        if focus != coordinator.lastFocus {
            coordinator.lastFocus = focus
            if let focus {
                coordinator.bring(focus, into: scroll, bottomCover: bottomCover)
            }
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var host: UIHostingController<AnyView>?
        var insets = UIEdgeInsets.zero
        var aspect: CGFloat = 1
        var lastFocus: CGRect?
        var laidOut = CGSize.zero
        var activity: ZoomActivity?
        var onTap: ((CGPoint, CGSize) -> Void)?
        var detail: CGFloat = 1

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            host?.view
        }

        @objc func tapped(_ tap: UITapGestureRecognizer) {
            guard let view = host?.view else { return }
            // In the content's own (unzoomed) coordinates.
            onTap?(tap.location(in: view), view.bounds.size)
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            center(scrollView)
        }

        // Busy from the first move until a moment after the photo settles.
        func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
            activity?.busyUntil = .distantFuture
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            settle()
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            activity?.busyUntil = .distantFuture
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate { settle() }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            settle()
        }

        func settle() {
            activity?.busyUntil = Date().addingTimeInterval(0.3)
        }

        // At the starting zoom the photo is as wide as the screen. Lay it out again only for a new photo or screen size.
        func layout(_ scroll: UIScrollView) {
            let width = scroll.bounds.width
            guard width > 0, let view = host?.view else { return }
            let size = CGSize(width: width * detail, height: width * aspect * detail)
            if size != laidOut {
                laidOut = size
                scroll.minimumZoomScale = 0.01
                scroll.zoomScale = 1
                view.transform = .identity
                view.frame = CGRect(origin: .zero, size: size)
                scroll.contentSize = size
                let fitWidth = 1 / detail
                // Start filling the whole screen, under the floating bars, like a viewfinder:
                // as wide as the screen, or for a short photo as tall as it.
                let fill = max(fitWidth, scroll.bounds.height / size.height)
                let visibleHeight = scroll.bounds.height - insets.top - insets.bottom
                scroll.maximumZoomScale = max(5 * fitWidth, 2 * fill)
                scroll.minimumZoomScale = min(fitWidth, visibleHeight / size.height)
                scroll.zoomScale = fill
                center(scroll)
                // From the very top, in the middle sideways. Dragging still reaches every edge.
                let x = (scroll.contentSize.width - scroll.bounds.width) / 2
                scroll.contentOffset = CGPoint(x: max(-scroll.contentInset.left, x), y: 0)
            } else {
                center(scroll)
            }
        }

        // Smaller than the screen (zoomed out): keep the photo in the middle of the space between the bars.
        func center(_ scroll: UIScrollView) {
            let visibleWidth = scroll.bounds.width - insets.left - insets.right
            let visibleHeight = scroll.bounds.height - insets.top - insets.bottom
            let dx = max(0, (visibleWidth - scroll.contentSize.width) / 2)
            let dy = max(0, (visibleHeight - scroll.contentSize.height) / 2)
            scroll.contentInset = UIEdgeInsets(
                top: insets.top + dy, left: insets.left + dx,
                bottom: insets.bottom + dy, right: insets.right + dx
            )
        }

        // Scroll just enough that this part sits in view, above anything covering the bottom.
        func bring(_ focus: CGRect, into scroll: UIScrollView, bottomCover: CGFloat) {
            let size = scroll.contentSize
            let rect = CGRect(x: focus.minX * size.width, y: focus.minY * size.height,
                              width: focus.width * size.width, height: focus.height * size.height)
            let covered = max(insets.bottom, bottomCover)
            let top = scroll.contentOffset.y + insets.top
            let bottom = scroll.contentOffset.y + scroll.bounds.height - covered
            guard rect.minY < top || rect.maxY > bottom else { return }
            let visibleHeight = scroll.bounds.height - insets.top - covered
            let highest = -scroll.contentInset.top
            let lowest = max(highest, size.height - scroll.bounds.height + covered)
            let y = min(max(rect.midY - insets.top - visibleHeight * 0.4, highest), lowest)
            scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: y), animated: true)
        }
    }
}
