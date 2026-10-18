// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Topside",
    platforms: [.macOS(.v13)],
    targets: [
        // Pure, testable logic: layout, interaction reducer, battery mapping, clock formatting.
        .target(name: "TopsideCore"),
        // The app: AppKit/SwiftUI/IOKit glue.
        .executableTarget(name: "Topside", dependencies: ["TopsideCore"]),
        .testTarget(name: "TopsideCoreTests", dependencies: ["TopsideCore"]),
    ]
)
