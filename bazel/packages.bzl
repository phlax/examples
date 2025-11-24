load("@envoy_examples_env//:llvm_flag.bzl", "LLVM_ENABLED")
load("@envoy_example_wasm_cc//bazel:packages.bzl", "load_envoy_example_wasm_cc_packages")
load("@envoy_example_wasm_cc//bazel:toolchains_extra.bzl", "load_envoy_example_wasm_cc_toolchains_extra")

def load_envoy_examples_packages():
    load_envoy_example_wasm_cc_packages()
    if LLVM_ENABLED:
        load_envoy_example_wasm_cc_toolchains_extra()
