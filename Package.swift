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
        .target(
            name: "CampusDashboardWindowsCore",
            dependencies: [
                .product(name: "SwiftCrossUI", package: "swift-cross-ui"),
                .product(name: "DefaultBackend", package: "swift-cross-ui")
            ],
            path: "Sources/CampusDashboard",
            sources: [
                "Domain/Models.swift",
                "Fixtures/SyntheticFixtures.swift",
                "Services/ServiceContracts.swift",
                "Security/SecretStore.swift",
                "Connectors/Canvas/CanvasConfiguration.swift",
                "Connectors/Canvas/CanvasDTOs.swift",
                "Connectors/Canvas/CanvasConcurrencyGate.swift",
                "Connectors/Canvas/CanvasAPIConnector.swift",
                "Connectors/Canvas/CanvasSnapshotLoader.swift",
                "Windows/WindowsCredentialSecretStore.swift",
                "Windows/WindowsCanvasSnapshotMapper.swift",
                "Windows/WindowsDashboardState.swift",
                "Windows/CampusDashboardWindowsApp.swift"
            ],
            linkerSettings: [
                .linkedLibrary("advapi32")
            ]
        ),
        .executableTarget(
            name: "CampusDashboardWindows",
            dependencies: [
                "CampusDashboardWindowsCore",
                .product(name: "SwiftCrossUI", package: "swift-cross-ui"),
                .product(name: "DefaultBackend", package: "swift-cross-ui")
            ],
            path: "Sources/CampusDashboardWindowsApp"
        ),
        .testTarget(
            name: "CampusDashboardWindowsTests",
            dependencies: ["CampusDashboardWindowsCore"],
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
