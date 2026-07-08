// Copyright 2026 Andrew Voirol. Apache-2.0
//
// Bridge module that re-exports the llama.cpp XCFramework.
// This exists because SPM requires a source target to bridge
// a binaryTarget into a library product.
//
// Usage in app code:
//   import llama          // for C API functions
//   #if canImport(llama)  // for conditional compilation guards

@_exported import llama
