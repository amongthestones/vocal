// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Vocal",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "Vocal", targets: ["Vocal"])
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.18.0")
    ],
    targets: [
        .executableTarget(
            name: "Vocal",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio")
            ],
            path: "Sources/Vocal"
        ),
        .testTarget(
            name: "VocalTests",
            dependencies: ["Vocal"],
            path: "Tests/VocalTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
