{
  local c = import '../../common.jsonnet',
  local config = import '../../repo-configuration.libsonnet',
  local jvm_config = config.compiler.default_jvm_config,
  local s = self,
  local t(limit) = {timelimit: limit},

  setup:: {
    setup+: [
      ["cd", "./" + config.compiler.compiler_suite],
      ["mx", "hsdis", "||", "true"]
    ]
  },

  base(tags="build,test", cmd_suffix=[], extra_vm_args="", extra_unittest_args="", jvm_config_suffix=null, no_warning_as_error=false):: s.setup + {
    run+: [
      ["mx", "--strict-compliance",
         "--kill-with-sigquit",
         "gate",
         "--strict-mode",
         "--extra-vm-argument=-Dgraal.DumpOnError=true -Dgraal.PrintGraphFile=true -Dgraal.PrintBackendCFG=true" +
           (if extra_vm_args == "" then "" else " " + extra_vm_args)
      ] + (if extra_unittest_args != "" then [
        "--extra-unittest-argument=" + extra_unittest_args,
      ] else []) + (if no_warning_as_error then [
        "--no-warning-as-error"
      ] else []) + [
        "--tags=" + tags
      ] + cmd_suffix
    ],
    environment+: if jvm_config_suffix != null then {
      JVM_CONFIG: jvm_config + jvm_config_suffix
    } else {},
    targets: ["gate"],
    python_version: "3"
  },

  weekly:: {
    notify_groups: ["compiler_weekly"],
    targets: ["weekly"],
    timelimit: "1:30:00",
  },

  monthly:: {
    # No need for a dedicated mailing list for monthlies yet
    notify_groups: ["compiler_weekly"],
    targets: ["monthly"],
    timelimit: "2:00:00",
  },

  test:: s.base(no_warning_as_error=true),

  coverage:: s.base("build,coverage", ["--jacoco-omit-excluded", "--jacocout", "html"]) + {
    run+: [
      ["mx", "coverage-upload"],
      # GR-18258 ["mx", "sonarqube-upload", "-Dsonar.host.url=$SONAR_HOST_URL", "-Dsonar.projectKey=com.oracle.graal.compiler."jvm-config.default, "-Dsonar.projectName=GraalVM - Compiler ("jvm-config.default")", "--exclude-generated", "--skip-coverage"]
    ]
  },

  test_javabase:: s.base("build,javabasetest"),

  test_vec16:: s.base(extra_vm_args="-Dgraal.DetailedAsserts=true -XX:MaxVectorSize=16"),
  test_avx0:: s.base(extra_vm_args="-Dgraal.ForceAdversarialLayout=true", jvm_config_suffix="-avx0"),
  test_avx1:: s.base(extra_vm_args="-Dgraal.ForceAdversarialLayout=true", jvm_config_suffix="-avx1"),

  # Runs truffle tests in a mode similar to HotSpot's -Xcomp option
  # (i.e. compile immediately without background compilation).
  truffle_xcomp:: s.base("build,unittest",
    extra_vm_args="-Dpolyglot.engine.AllowExperimentalOptions=true " +
                  "-Dpolyglot.engine.CompileImmediately=true " +
                  "-Dpolyglot.engine.BackgroundCompilation=false " +
                  "-Dtck.inlineVerifierInstrument=false",
    extra_unittest_args="--very-verbose truffle") + {
      environment+: {"TRACE_COMPILATION": "true"},
      logs+: ["*/*_compilation.log"]
    },

  ctw:: s.base("build,ctw", no_warning_as_error=true),

  ctw_economy:: s.base("build,ctweconomy", extra_vm_args="-Dgraal.CompilerConfiguration=economy"),

  coverage_ctw:: s.base("build,ctw", ["--jacoco-omit-excluded", "--jacocout", "html"], extra_vm_args="-DCompileTheWorld.MaxClasses=5000" /*GR-23372*/) + {
    run+: [
      ["mx", "coverage-upload"]
    ],
    timelimit : "1:30:00"
  },

  # Runs some benchmarks as tests
  benchmarktest:: s.base("build,benchmarktest") + {
    run+: [
      # blackbox jmh test
      ["mx", "benchmark", "jmh-dist:GRAAL_COMPILER_MICRO_BENCHMARKS",
             "--fail-fast",
             "--",
             "-Djmh.ignoreLock=true",
             "--jvm-config=" + jvm_config,
             "--jvm=server",
             "--",
             ".*TestJMH.*" ],
      # whitebox jmh test
      ["mx", "benchmark", "jmh-whitebox:*",
             "--fail-fast",
             "--",
             "-Djmh.ignoreLock=true",
             "--jvm-config=" + jvm_config,
             "--jvm=server",
             "--",
             ".*TestJMH.*" ]
    ]
  },

  bootstrap:: s.base("build,bootstrap", no_warning_as_error=true),
  bootstrap_lite:: s.base("build,bootstraplite", no_warning_as_error=true),
  bootstrap_full:: s.base("build,bootstrapfullverify", no_warning_as_error=true),
  bootstrap_economy:: s.base("build,bootstrapeconomy", no_warning_as_error=true, extra_vm_args="-Dgraal.CompilerConfiguration=economy"),

  style:: c.eclipse + c.jdt + s.base("style,fullbuild,javadoc"),

  avx3:: {
    capabilities+: ["avx512"],
    environment+: {
      JVM_CONFIG: jvm_config + "-avx3"
    }
  },

  many_cores:: {
    capabilities+: ["manycores"]
  },

  # Returns true if `str` contains `needle` as a substring.
  contains(str, needle):: std.findSubstr(needle, str) != [],

  # Returns the value of the `name` field if it exists in `obj` otherwise `default`.
  get(obj, name, default=null)::
      if obj == null then default else
      if std.objectHas(obj, name) then obj[name] else default,

  # This map defines the builders that run as gates. Each key in this map
  # must correspond to the name of a build created by `make_build`.
  # Each value in this map is an object that overrides or extends the
  # fields of the denoted build.
  local gates = {
    # Darwin AMD64
    "gate-compiler-test-labsjdk-17-darwin-amd64": t("1:00:00") + c.mach5_target,

    # Darwin AArch64
    "gate-compiler-test-labsjdk-17-darwin-aarch64": t("1:00:00"),

    # Windows AMD64
    "gate-compiler-test-labsjdk-11-windows-amd64": t("55:00"),
    "gate-compiler-test-labsjdk-17-windows-amd64": t("55:00") + c.mach5_target,

    # Linux AMD64
    "gate-compiler-style-labsjdk-17-linux-amd64": t("45:00"),
    "gate-compiler-test-labsjdk-11-linux-amd64": t("55:00"),
    "gate-compiler-test-labsjdk-17-linux-amd64": t("55:00") + c.mach5_target,
    "gate-compiler-ctw-labsjdk-11-linux-amd64": c.mach5_target,
    "gate-compiler-ctw-labsjdk-17-linux-amd64": c.mach5_target,
    "gate-compiler-ctw_economy-labsjdk-11-linux-amd64": {},
    "gate-compiler-ctw_economy-labsjdk-17-linux-amd64": {},
    "gate-compiler-benchmarktest-labsjdk-11-linux-amd64": {},
    "gate-compiler-benchmarktest-labsjdk-17-linux-amd64": {},
    "gate-compiler-truffle_xcomp-labsjdk-17-linux-amd64": t("1:30:00"),

    # Linux AArch64
    "gate-compiler-test-labsjdk-11-linux-aarch64": t("1:50:00"),
    "gate-compiler-ctw-labsjdk-11-linux-aarch64": t("1:50:00"),
    "gate-compiler-ctw_economy-labsjdk-11-linux-aarch64": t("1:50:00"),

    # Bootstrap testing
    "gate-compiler-bootstrap_lite-labsjdk-11-darwin-amd64": t("1:00:00") + c.mach5_target,
    "gate-compiler-bootstrap_lite-labsjdk-17-darwin-amd64": t("1:00:00") + c.mach5_target,
    "gate-compiler-bootstrap_full-labsjdk-17-linux-amd64": s.many_cores + c.mach5_target
  },

  # This map defines the builders that run weekly. Each key in this map
  # must correspond to the name of a build created by `make_build`.
  # Each value in this map is an object that overrides or extends the
  # fields of the denoted build.
  local weeklies = {
    "weekly-compiler-test-labsjdk-11-darwin-amd64": {},
    "weekly-compiler-test-labsjdk-11-darwin-aarch64": {},
    "weekly-compiler-test_vec16-labsjdk-17-linux-amd64": {},
    "weekly-compiler-test_avx0-labsjdk-17-linux-amd64": {},
    "weekly-compiler-test_avx1-labsjdk-17-linux-amd64": {},
    "weekly-compiler-test_javabase-labsjdk-17-linux-amd64": {},
    "weekly-compiler-benchmarktest-labsjdk-17Debug-linux-amd64": {},
    "weekly-compiler-coverage_ctw-labsjdk-11-linux-amd64": t("2:00:00"),
    "weekly-compiler-coverage-labsjdk-17-linux-amd64": t("1:50:00"),
    "weekly-compiler-coverage-labsjdk-11-linux-aarch64": t("1:50:00"),
    "weekly-compiler-coverage_ctw-labsjdk-17-linux-amd64": {},
    "weekly-compiler-coverage_ctw-labsjdk-11-linux-aarch64": {},
    "weekly-compiler-test-labsjdk-17Debug-linux-amd64": {}
  },

  # This map defines overrides and field extensions for monthly builds.
  local monthlies = {},

  # Creates a CI build object.
  #
  # jdk: JDK version (e.g. "17", "17Debug")
  # os_arch: OS and architecture (e.g., "linux-amd64", "darwin-aarch64")
  # task: name of an object field in self defining the JDK and platform agnostic build details (e.g. "test")
  # extra_tasks: object whose fields define additional tasks to those defined in self
  # gates_manifest: specification of gate builds (e.g. see `gates` local variable)
  # gates_manifest: specification of weekly builds (e.g. see `weeklies` local variable)
  # gates_manifest: specification of monthly builds (e.g. see `monthlies` local variable)
  # returns: an object with a single "build" field
  make_build(jdk, os_arch, task, suite="compiler", extra_tasks={},
             include_common_os_arch=true,
             gates_manifest=gates,
             weeklies_manifest=weeklies,
             monthlies_manifest=monthlies):: {
    local base_name = "%s-%s-labsjdk-%s-%s" % [suite, task, jdk, os_arch],
    local gate_name = "gate-" + base_name,
    local weekly_name = "weekly-" + base_name,
    local monthly_name = "monthly-" + base_name,
    local is_gate = std.objectHas(gates_manifest, gate_name),
    local is_weekly = std.objectHas(weeklies_manifest, weekly_name),
    local is_monthly = !is_gate && !is_weekly,
    local is_windows = $.contains(os_arch, "windows"),
    local extra = if is_gate then
        $.get(gates_manifest, gate_name, {})
      else if is_weekly then
        $.get(weeklies_manifest, weekly_name, {})
      else
        $.get(monthlies_manifest, monthly_name, {}),

    build: {
      name: if is_gate then gate_name else if is_weekly then weekly_name else monthly_name
    } +
      (s + extra_tasks)[task] +
      c["labsjdk%s" % jdk] +
      (if include_common_os_arch then c[std.strReplace(os_arch, "-", "_")] else {}) +
      (if is_weekly then s.weekly else {}) +
      (if is_monthly then s.monthly else {}) +
      (if is_windows then c.devkits["windows-jdk%s" % jdk] else {}) +
      extra,
  },

  # Checks that each key in `manifest` corresponds to the name of a build in `builds`.
  #
  # manifest: a map whose keys must be a subset of the build names in `builds`
  # manifest_file: file in which the value of `manifest` originates
  # manifest_name: name of the field providing the value of `manifest`
  check_manifest(manifest, builds, manifest_file, manifest_name): {
    local manifest_keys = std.set(std.objectFields(manifest)),
    local build_names = std.set([b.name for b in builds]),
    local unknown = std.setDiff(manifest_keys, build_names),

    result: if unknown != [] then
        error "%s: name(s) in %s manifest that do not match a defined builder:\n  %s\nDefined builders:\n  %s" % [
          manifest_file,
          manifest_name,
          std.join("\n  ", std.sort(unknown)),
          std.join("\n  ", std.sort(build_names))]
      else
        true
  },

  # Builds run on all platforms (platform = JDK + OS + ARCH)
  local all_platforms_builds = [self.make_build(jdk, os_arch, task).build
    for jdk in [
      "11",
      "17",
      "19"
    ]
    for os_arch in [
      "linux-amd64",
      "linux-aarch64",
      "darwin-amd64",
      "darwin-aarch64",
      "windows-amd64"
    ]
    for task in [
      "test",
      "truffle_xcomp",
      "ctw",
      "ctw_economy",
      "coverage",
      "coverage_ctw",
      "benchmarktest",
      "bootstrap_lite",
      "bootstrap_full"
    ]
  ],

  # Builds run on only on linux-amd64-jdk17
  local linux_amd64_jdk17_builds = [self.make_build("17", "linux-amd64", task).build
    for task in [
      "test_vec16",
      "test_avx0",
      "test_avx1",
      "test_javabase",
      "style"
    ]
  ],

  # Builds run on only on linux-amd64-jdk17Debug
  local linux_amd64_jdk17Debug_builds = [self.make_build("17Debug", "linux-amd64", task).build
    for task in [
      "benchmarktest",
      "test"
    ]
  ],

  # Complete set of builds defined in this file
  local all_builds =
    all_platforms_builds +
    linux_amd64_jdk17_builds +
    linux_amd64_jdk17Debug_builds,

  builds: if
      self.check_manifest(gates,     all_builds, std.thisFile, "gates").result &&
      self.check_manifest(weeklies,  all_builds, std.thisFile, "weeklies").result &&
      self.check_manifest(monthlies, all_builds, std.thisFile, "monthlies").result
    then
      all_builds + (import '../ci_includes/bootstrap_extra.libsonnet').builds
}
