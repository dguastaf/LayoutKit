// Copyright 2016 LinkedIn Corp.
// Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
// You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.

import CoreGraphics

/**
 The frame of a layout and the frames of its sublayouts.
 */
public struct LayoutArrangement {
    public let layout: Layout
    public let frame: CGRect
    public let sublayouts: [LayoutArrangement]

    public init(layout: Layout, frame: CGRect, sublayouts: [LayoutArrangement]) {
        self.layout = layout
        self.frame = frame
        self.sublayouts = sublayouts
    }

    /**
     Creates the views for the layout and adds them as subviews to the provided view.
     Existing subviews of the provided view will be removed.
     If no view is provided, then a new one is created and returned.
     
     MUST be run on the main thread.

     - parameter view: The layout's views will be added as subviews to this view, if provided.
     - parameter direction: The natural direction of the layout (default: .LeftToRight).
     If it does not match the user's language direction, then the layout's views will be flipped horizontally.
     Only provide this parameter if you want to test the flipped version of your layout,
     or if your layouts are declared for right-to-left languages and you want them to get flipped for left-to-right languages.

     - returns: The root view. If a view was provided, then the same view will be returned, otherwise, a new one will be created.
     */
    public func makeViews(in view: View? = nil, direction: UserInterfaceLayoutDirection = .LeftToRight) -> View {
        return makeViews(in: view, direction: direction, prepareAnimation: false)
    }

    /**
     Prepares the view to be animated to this arrangement.

     Call `prepareAnimation(for:direction)` before the animation block.
     Call the returned animation's `apply()` method inside the animation block.

     ```
     let animation = nextLayout.arrangement().prepareAnimation(for: rootView, direction: .RightToLeft)
     View.animateWithDuration(5.0, animations: {
         animation.apply()
     })
     ```
     
     Subviews are reparented for the new arrangement, if necessary, but frames are adjusted so locations don't change.
     No frames or configurations of the new arrangement are applied until `apply()` is called on the returned animation object.
     
     MUST be run on the main thread.
     */
    public func prepareAnimation(for view: View, direction: UserInterfaceLayoutDirection = .LeftToRight) -> Animation {
        makeViews(in: view, direction: direction, prepareAnimation: true)
        return Animation(arrangement: self, rootView: view, direction: direction)
    }

    /**
     Helper function for `makeViews(in:direction:)` and `prepareAnimation(for:direction:)`.
     See the documentation for those two functions.
     */
    private func makeViews(in view: View? = nil, direction: UserInterfaceLayoutDirection, prepareAnimation: Bool) -> View {
        let recycler = ViewRecycler(rootView: view)
        let views = makeSubviews(from: recycler, prepareAnimation: prepareAnimation)
        let rootView: View

        if let view = view {
            for subview in views {
                view.addSubview(subview, maintainCoordinates: prepareAnimation)
            }
            rootView = view
        } else if let view = views.first where views.count == 1 {
            // We have a single view so it is our root view.
            rootView = view
        } else {
            // We have multiple views so create a root view.
            rootView = View(frame: frame)
            for subview in views {
                if !prepareAnimation {
                    // Unapply the offset that was applied in makeSubviews()
                    subview.frame.offsetInPlace(dx: -frame.origin.x, dy: -frame.origin.y)
                }
                rootView.addSubview(subview)
            }
        }
        recycler.purgeViews()

        if !prepareAnimation {
            handleLayoutDirection(rootView, direction: direction)
        }
        return rootView
    }

    /// Horizontally flips the view frames if direction does not match the user's language direction.
    private func handleLayoutDirection(view: View, direction: UserInterfaceLayoutDirection) {
        if Application.sharedApplication().userInterfaceLayoutDirection != direction {
            flipSubviewsHorizontally(view)
        }
    }

    /// Flips the right and left edges of the view's subviews.
    private func flipSubviewsHorizontally(view: View) {
        for subview in view.subviews {
            subview.frame.origin.x = view.frame.width - subview.frame.maxX
            flipSubviewsHorizontally(subview)
        }
    }

    /// Returns the views for the layout and all of its sublayouts.
    private func makeSubviews(from recycler: ViewRecycler, prepareAnimation: Bool) -> [View] {
        let subviews = sublayouts.flatMap({ (sublayout: LayoutArrangement) -> [View] in
            return sublayout.makeSubviews(from: recycler, prepareAnimation: prepareAnimation)
        })
        // If we are preparing an animation, then we don't want to update frames or configure views.
        if let view = layout.makeView(from: recycler) {
            if !prepareAnimation {
                view.frame = frame
                layout.configure(baseTypeView: view)
            }
            for subview in subviews {
                // If a view gets reparented and we are preparing an animation, then
                // make sure that its absolute position on the screen does not change.
                view.addSubview(subview, maintainCoordinates: prepareAnimation)
            }
            return [view]
        } else {
            if !prepareAnimation {
                for subview in subviews {
                    subview.frame.offsetInPlace(dx: frame.origin.x, dy: frame.origin.y)
                }
            }
            return subviews
        }
    }
}

extension View {

    /**
     Similar to `addSubview()` except if `maintainCoordinates` is true, then the view's frame
     will be adjusted so that its absolute position on the screen does not change.
     
     It doesn't do anything of view is already a subview.
     */
    private func addSubview(view: View, maintainCoordinates: Bool) {
        if view.superview == self {
            return
        }
        if maintainCoordinates {
            let frame = view.convertToAbsoluteCoordinates(view.frame)
            addSubview(view)
            view.frame = view.convertFromAbsoluteCoordinates(frame)
        } else {
            addSubview(view)
        }
    }
}

