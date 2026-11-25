// swift-tools-version:6.0
// Athlos — a time tracker that runs fully on your Mac.
// Build: `make app` (builds the .app) · Tests: `make test`
import PackageDescription
import Foundation

// Without Xcode (Command Line Tools only) tests build with the default SDK and the app with the 26.x SDK
// (see scripts/build_app.sh). With ATHLOS_CORE_ONLY=1 the app target is left out of the package.
let coreOnly = ProcessInfo.processInfo.environment["ATHLOS_CORE_ONLY"] == "1"

var targets: [Target] = [
    // Pure logic: models, store, timer, statistics, backup. No UI → testable.
    .target(name: "AthlosCore"),
    .testTarget(name: "AthlosCoreTests", dependencies: ["AthlosCore"]),
]
var products: [Product] = [.library(name: "AthlosCore", targets: ["AthlosCore"])]
if !coreOnly {
    // SwiftUI app (windows, menu bar, notifications, shortcuts).
    targets.append(.executableTarget(name: "Athlos", dependencies: ["AthlosCore"]))
    products.append(.executable(name: "Athlos", targets: ["Athlos"]))
}

let package = Package(
    name: "Athlos",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: products,
    targets: targets,
    swiftLanguageModes: [.v6]
)
