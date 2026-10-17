#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/relay-tests.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/Sources" "$test_dir/Tests"
cp "$repo_root/App/Shared/RelayReliability.swift" "$test_dir/Sources/"
cp "$repo_root/RelayTests/"*.swift "$test_dir/Tests/"
cat > "$test_dir/Package.swift" <<'SWIFT'
// swift-tools-version: 5.10
import PackageDescription
let package = Package(name: "RelayReliability", platforms: [.macOS(.v14)], targets: [
    .target(name: "RelayReliability", path: "Sources"),
    .testTarget(name: "RelayTests", dependencies: ["RelayReliability"], path: "Tests")
])
SWIFT
swift test --package-path "$test_dir"
