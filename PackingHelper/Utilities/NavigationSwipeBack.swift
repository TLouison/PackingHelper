//
//  NavigationSwipeBack.swift
//  PackingHelper
//
//  Keeps the edge swipe-back gesture working on screens that hide the
//  navigation bar (e.g. TripDetailView), where UIKit disables it by default.
//

import UIKit

extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // Only allow popping when there's something to pop back to
        viewControllers.count > 1
    }
}
