// swift-tools-version: 6.0

import PackageDescription

#if os(Windows)
let package = Package(
    name: "CampusDashboard",
    products: [
        .executable(name: "CampusDashboardWindows", targets: ["CampusDashboardWindows"])
    ],
    dependencies: [
        .package(url: "https://github.com/moreSwift/swift-cross-ui", exact: "0.9.0")
    ],
    targets: [
        .executableTarget(
            name: "CampusDashboardWindows",
            dependencies: [
                .product(name: "SwiftCrossUI", package: "swift-cross-ui"),
                .product(name: "DefaultBackend", package: "swift-cross-ui")
            ],
            path: "Sources/CampusDashboard",
            sources: [
                "Domain/Models.swift",
                "Fixtures/SyntheticFixtures.swift",
                "Windows/CampusDashboardWindowsApp.swift"
            ]
        ),
        .testTarget(
            name: "CampusDashboardWindowsTests",
            dependencies: ["CampusDashboardWindows"],
            path: "Tests/CampusDashboardWindowsTests"
        )
    ]
)
#else
let package = Package(
    name: "CampusDashboard",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CampusDashboard", targets: ["CampusDashboard"])
    ],
    targets: [
        .executableTarget(
            name: "CampusDashboard",
            path: "Sources/CampusDashboard",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("EventKit"),
                .linkedFramework("Network"),
                .linkedFramework("Security"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("UserNotifications"),
                .linkedFramework("WebKit")
            ]
        ),
        .testTarget(
            name: "CampusDashboardTests",
            dependencies: ["CampusDashboard"],
            path: "Tests/CampusDashboardTests",
            resources: [.copy("Fixtures/Canvas"), .copy("Fixtures/SIweb"), .copy("Fixtures/Stage15")]
        )
    ]
)
#endif
