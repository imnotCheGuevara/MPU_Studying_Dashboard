// swift-tools-version: 6.0

import PackageDescription

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
