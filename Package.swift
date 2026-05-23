// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MyTodo",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "TodoCore", targets: ["TodoCore"]),
        .executable(name: "MyTodo", targets: ["MyTodo"]),
        .executable(name: "TodoCoreChecks", targets: ["TodoCoreChecks"])
    ],
    targets: [
        .target(name: "TodoCore", path: "Sources/TodoCore"),
        .executableTarget(name: "MyTodo", dependencies: ["TodoCore"], path: "Sources/MyTodo"),
        .executableTarget(name: "TodoCoreChecks", dependencies: ["TodoCore"], path: "Tests/TodoCoreChecks")
    ]
)
