import Foundation

let verbose = CommandLine.arguments.contains("--verbose")

private let timestamp = ISO8601DateFormatter()

func log(_ message: String) {
    print("\(timestamp.string(from: Date())) \(message)")
}
