// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Sheen",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "Sheen",
            targets: ["Sheen"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/kishikawakatsumi/KeychainAccess", from: "4.2.0"),
        .package(url: "https://github.com/ankitra/libgit2-apple", branch: "main")
    ],
    targets: [
        .target(
            name: "Sheen",
            dependencies: [
                .product(name: "KeychainAccess", package: "KeychainAccess"),
                .product(name: "Git", package: "libgit2-apple"),
                .product(name: "CGit", package: "libgit2-apple"),
            ],
            publicHeadersPath: "include"
        )
    ]
)
