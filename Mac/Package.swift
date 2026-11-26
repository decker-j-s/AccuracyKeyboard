// swift-tools-version:5.9
// The Mac version, built with Swift Package Manager instead of Xcode,
// so it can be built and installed with one script (build.sh).
import PackageDescription

let package = Package(
    name: "CheckChinese",
    platforms: [.macOS(.v14)],
    targets: [
        // Sources/CheckChinese: the Mac window and service.
        // Sources/CheckChinese/Shared: links to the iPhone keyboard's files,
        // so both versions use the same prompt, API call, and diff.
        .executableTarget(name: "CheckChinese", path: "Sources/CheckChinese")
    ]
)
