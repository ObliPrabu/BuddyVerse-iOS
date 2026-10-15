import Foundation

/// Firebase and Foundation hand their completion/timer callbacks to us as
/// `@Sendable` closures, even though every one of them in this app is
/// delivered on the main thread (Firestore calls back on the main queue by
/// default, and the timers are scheduled from the main run loop). SwiftUI
/// views and the UI-facing managers are main-actor isolated, so touching
/// their state from inside such a closure needs the compiler to be told what
/// we already know: that we are on the main actor. This does that, and falls
/// back to hopping onto the main queue first if a callback ever does arrive
/// off-main, so it can never run UI code on the wrong thread.
func runOnMain(_ body: @escaping @MainActor () -> Void) {
    if Thread.isMainThread {
        MainActor.assumeIsolated(body)
    } else {
        DispatchQueue.main.async { MainActor.assumeIsolated(body) }
    }
}
