load("@llvm_toolchain//:toolchains.bzl", "llvm_register_toolchains")

def load_envoy_example_wasm_cc_toolchains_extra():
    llvm_register_toolchains()
