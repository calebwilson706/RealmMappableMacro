// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "RealmMappable",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17), .watchOS(.v10), .macCatalyst(.v17)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "RealmMappable",
            targets: ["RealmMappable"]
        ),
        .executable(
            name: "RealmMappableClient",
            targets: ["RealmMappableClient"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0-latest"),
        .package(url: "https://github.com/realm/realm-swift", from: "20.0.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        // Macro implementation that performs the source transformation of a macro.
        .macro(
            name: "RealmMappableMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax")
            ]
        ),

        // Library that exposes a macro as part of its API, which is used in client programs.
        .target(name: "RealmMappable", dependencies: ["RealmMappableMacros"]),

        // A client of the library, which is able to use the macro in its own code.
        .executableTarget(
            name: "RealmMappableClient",
            dependencies: [
                "RealmMappable",
                .product(name: "RealmSwift", package: "realm-swift")
            ]
        ),

        // A test target used to develop the macro implementation.
        .testTarget(
            name: "RealmMappableTests",
            dependencies: [
                "RealmMappableMacros",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ]
        ),
    ]
)
