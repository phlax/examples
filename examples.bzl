load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

def _example_name(f):
    workspace = f.owner.workspace_name
    if "envoy-example-" in workspace:
        return workspace.split("envoy-example-", 1)[1].split("~", 1)[0].split("+", 1)[0]
    return f.owner.name.split("/")[0]

def _example_files_impl(ctx):
    excluded = ctx.attr._exclude[BuildSettingInfo].value
    return [DefaultInfo(files = depset([
        f
        for f in ctx.files.srcs
        if _example_name(f) not in excluded
    ]))]

example_files = rule(
    implementation = _example_files_impl,
    attrs = {
        "srcs": attr.label_list(allow_files = True),
        "_exclude": attr.label(default = Label("//:exclude")),
    },
)

def _example_runner_impl(ctx):
    excluded = ctx.attr._exclude[BuildSettingInfo].value
    inputs = [
        f
        for target, example in ctx.attr.outputs.items()
        if example not in excluded
        for f in target[DefaultInfo].files.to_list()
        if f.basename.endswith(ctx.attr.suffix)
    ]
    out = ctx.actions.declare_file(ctx.label.name + ".txt")
    ctx.actions.run_shell(
        inputs = inputs + [ctx.file.runner],
        outputs = [out],
        command = '"$1" "${@:3}" 2>&1 | tee "$2"; exit "${PIPESTATUS[0]}"',
        arguments = [ctx.file.runner.path, out.path] + [f.path for f in inputs],
        mnemonic = "ExampleRunner",
        progress_message = "Running %s" % ctx.label.name,
        execution_requirements = {"no-remote-exec": "1", "no-cache": "1"},
    )
    return [DefaultInfo(files = depset([out]))]

example_runner = rule(
    implementation = _example_runner_impl,
    attrs = {
        "outputs": attr.label_keyed_string_dict(allow_files = True),
        "runner": attr.label(allow_single_file = True),
        "suffix": attr.string(mandatory = True),
        "_exclude": attr.label(default = Label("//:exclude")),
    },
)

def envoy_example(name, shared = ":shared_files", common_fun = ":verify-common.sh"):
    native.filegroup(
        name = "%s_files" % name,
        srcs = native.glob(
            ["%s/**/*" % name],
            exclude = [
                "%s/**/node_modules/**" % name,
                "%s/**/dist/**" % name,
                "%s/**/target/**" % name,
            ],
        ),
    )

    native.genrule(
        name = "%s_dir" % name,
        outs = ["%s_dir.tar" % name],
        cmd = """
        read -ra SHARED_PATHS <<< "$(locations %s)"
        SHARED_DIR=$$(echo $${SHARED_PATHS[0]} | cut -d/ -f1)
        # This is a bit hacky and may not work in all bazel situations, but works for now
        if [[ $$SHARED_DIR == "external" ]]; then
            SHARED_DIR=$$(echo $${SHARED_PATHS[0]} | cut -d/ -f-3)
        fi
        EXAMPLE=%s
        read -ra EXAMPLE_PATHS <<< "$(locations %s_files)"
        EXAMPLE_DIR=$$(echo $${EXAMPLE_PATHS[0]} | cut -d/ -f1)
        # This is a bit hacky and may not work in all bazel situations, but works for now
        if [[ $$EXAMPLE_DIR == "external" ]]; then
            EXAMPLE_DIR=$$(echo $$EXAMPLE_PATHS | cut -d/ -f-3)
        fi
        TARGET_DIR=$$(dirname $$EXAMPLE_DIR)
        tar chf $@ -C $$TARGET_DIR --exclude="$$(basename "$@")" .
        """ % (shared, name, name),
        tools = [
            common_fun,
            shared,
            "%s_files" % name,
        ],
    )

def envoy_examples(examples):
    native.filegroup(
        name = "shared_files",
        srcs = native.glob(
            ["shared/**/*"],
            exclude = [
                "**/*~",
                "**/.*",
                "**/#*",
                ".*/**/*",
            ],
        ),
    )

    for example in examples:
        envoy_example(name = example, shared = ":shared_files")
        sh_test(
            name = "%s_result" % example,
            srcs = [":verify_example.sh"],
            args = [example, "$(location :%s_dir)" % example],
            data = [":%s_dir" % example],
            env = {"BUILDX_BAKE_ENTITLEMENTS_FS": "0"},
            tags = ["requires-docker", "no-sandbox", "no-remote-exec", "local"],
            size = "large",
            timeout = "long",
        )

    native.test_suite(
        name = "verify_examples",
        tests = [":%s_result" % example for example in examples],
    )
