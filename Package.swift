// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FileExplorer",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "FileExplorer",
            targets: ["FileExplorer"]
        )
    ],
    targets: [
        .systemLibrary(
            name: "CiMobileDevice",
            path: "CiMobileDevice",
            pkgConfig: "libimobiledevice-1.0",
            providers: [
                .brew(["libimobiledevice"])
            ]
        ),
        .executableTarget(
            name: "FileExplorer",
            dependencies: ["CiMobileDevice"],
            path: "app",
            exclude: ["Info.plist"],
            resources: [
                .copy("Resources/Icons"),
                .copy("Resources/AppIcon.icns"),
                .copy("Resources/AppIcon.svg")
            ]
        ),
        .testTarget(
            name: "FileExplorerTests",
            dependencies: ["FileExplorer"],
            path: "Tests"
        )
    ]
)
