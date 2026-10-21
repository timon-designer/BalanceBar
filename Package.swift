// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BalanceBar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "BalanceBar",
            path: "Sources/BalanceBar"
        )
    ]
)
