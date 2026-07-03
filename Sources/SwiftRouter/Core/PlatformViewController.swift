#if canImport(UIKit)
import UIKit
/// The platform's view controller type — `UIViewController` on iOS.
public typealias PlatformViewController = UIViewController
#else
/// Minimal stand-in so the routing pipeline compiles and its tests run
/// via `swift test` on platforms without UIKit.
open class PlatformViewController {
    public init() {}
}
#endif
