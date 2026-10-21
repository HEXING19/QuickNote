// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "QuickNote", platforms: [.macOS(.v13)], products: [.executable(name: "QuickNote", targets: ["QuickNote"])], targets: [.target(name: "QuickNoteCore"), .executableTarget(name: "QuickNote", dependencies: ["QuickNoteCore"]), .testTarget(name: "QuickNoteCoreTests", dependencies: ["QuickNoteCore"])], swiftLanguageModes: [.v5])
