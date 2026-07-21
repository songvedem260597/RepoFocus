// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "RepoFocus",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "RepoFocus", targets: ["RepoFocus"])
    ],
    targets: [
        .target(
            name: "RepoFocusCore",
            linkerSettings: [
                .linkedFramework("Security")
            ]
        ),
        .executableTarget(
            name: "RepoFocus",
            dependencies: ["RepoFocusCore"]
        ),
        .testTarget(
            name: "RepoFocusCoreTests",
            dependencies: ["RepoFocusCore"],
            swiftSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
                ])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
                ])
            ]
        )
    ]
)
