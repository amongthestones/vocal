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
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.18.0"),
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", exact: "1.1.1")
    ],
    targets: [
        .executableTarget(
            name: "Vocal",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "WhisperKit", package: "WhisperKit")
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
