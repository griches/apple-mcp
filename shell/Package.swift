// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MojoShell",
    platforms: [
        .macOS(.v14),
    ],
    targets: [
        .executableTarget(
            name: "MojoShell",
            path: "Sources/MojoShell"
        ),
        .testTarget(
            name: "MojoShellTests",
            dependencies: ["MojoShell"],
            path: "Tests/MojoShellTests"
        ),
    ]
)
