// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MeetingSplitter",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "MeetingSplitter",
            targets: ["MeetingSplitter"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/swiftlang/swift-testing.git",
            revision: "swift-6.3.2-RELEASE"
        )
    ],
    targets: [
        .executableTarget(
            name: "MeetingSplitter"
        ),
        .testTarget(
            name: "MeetingSplitterTests",
            dependencies: [
                "MeetingSplitter",
                .product(name: "Testing", package: "swift-testing")
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-L",
                    "/Library/Developer/CommandLineTools/Library/Developer/usr/lib",
                    "-Xlinker",
                    "-rpath",
                    "-Xlinker",
                    "/Library/Developer/CommandLineTools/Library/Developer/usr/lib"
                ])
            ]
        )
    ]
)
