// gen1recomp iOS native bridge: foldable hinge state (iPhone Duo).
//
// Exposed to Lua as love.system.getHinge() -> status, angle through liblove's
// wrap_System.cpp (see mobile/ios/patch_love_src.py); src/core/DuoPosture.lua
// polls it and lays the game and touch pad out per posture.
//
// UIHingeInteraction (iOS 27.1) is looked up at runtime rather than named, so
// this file builds with any iOS SDK; where UIKit lacks it the status is -1
// and Lua keeps the stock layouts.
//
// Status codes: -1 no hinge, 0 unknown, 1 closed, 2 partially open, 3 fully
// open. The angle is an integer in tenths of a degree so the C++ side needs
// no floating-point objc_msgSend variant.

import UIKit

// UIHingeInteraction's initializer, declared here so the class can be created
// from a runtime lookup (selector initWithUpdateHandler:).
@objc private protocol GRHingeInteractionType {
    init(updateHandler: @escaping (AnyObject, AnyObject) -> Void)
}

@objc(GRHingeBridge)
public final class GRHingeBridge: NSObject {

    private static var status: Int = -1
    private static var angleTenths: Int = 0
    private static weak var attachedView: UIView?
    private static var interaction: AnyObject?

    /// love.system.getHinge() status code (see the header).
    @objc public static func hingeStatus() -> Int {
        attachIfNeeded()
        return status
    }

    /// Last hinge angle in tenths of a degree (1800 = flat).
    @objc public static func hingeAngleTenths() -> Int {
        return angleTenths
    }

    // MARK: - Attachment

    private static func keyWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let active = scenes.first { $0.activationState == .foregroundActive }
            ?? scenes.first
        return active?.windows.first { $0.isKeyWindow } ?? active?.windows.first
    }

    /// Adds the interaction to the key window, moving it when the window
    /// changes (the Duo hands the app between its displays). UIKit
    /// interactions are main-thread only; off the main thread the status
    /// stays -1 rather than touching UIKit.
    private static func attachIfNeeded() {
        guard Thread.isMainThread else { return }
        guard let hingeClass = NSClassFromString("UIHingeInteraction") else { return }
        guard let window = keyWindow() else { return }
        if attachedView === window, interaction != nil { return }
        if let old = interaction as? UIInteraction {
            old.view?.removeInteraction(old)
        }
        let type = unsafeBitCast(hingeClass, to: GRHingeInteractionType.Type.self)
        let created = type.init(updateHandler: { _, update in
            GRHingeBridge.apply((update as? NSObject)?.value(forKey: "hinge") as? NSObject)
        })
        guard let hinge = created as? UIInteraction else { return }
        window.addInteraction(hinge)
        interaction = hinge
        attachedView = window
    }

    /// Reads a UIHinge through key-value coding: status is a UIHinge.Status
    /// raw value (0 unknown, 1 closed, 2 partially open, 3 fully open).
    private static func apply(_ hinge: NSObject?) {
        guard let hinge else {
            status = -1
            angleTenths = 0
            return
        }
        let raw = (hinge.value(forKey: "status") as? NSNumber)?.intValue ?? 0
        status = (1...3).contains(raw) ? raw : 0
        let radians = (hinge.value(forKey: "angle") as? NSNumber)?.doubleValue ?? 0
        angleTenths = Int((radians * 180 / .pi * 10).rounded())
    }
}
