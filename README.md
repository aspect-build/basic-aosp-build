# Basic AOSP build on Aspect Workflows

Builds the Android Open Source Project from source, locally or with remote execution
against an [Aspect Workflows](https://aspect.build) deployment. AOSP's build system speaks
RBE through [reclient](https://github.com/bazelbuild/reclient); this repo wires that at
scale: a full build executes 81k+ actions on a Buildbarn-backed worker fleet.

The default build is Android Automotive (AAOS) for arm64, from `android-17.0.0_r1`.

Every CI run of the
[AOSP Build workflow](https://github.com/aspect-build/basic-aosp-build/actions/workflows/aosp-build.yaml)
is public and uploads its complete build logs as artifacts.

## Measured results

Four benchmarks of the same build, spanning worst case to steady state. These were
measured on `android-14.0.0_r22` / `aosp_arm64-userdebug` (176,702 ninja actions), which
was the default at the time. The automotive target above has not been benchmarked yet:

| Benchmark | Build time | Run |
|---|---|---|
| First build: fresh runner, cold `repo sync` | 1h 16m | [31758099068](https://github.com/aspect-build/basic-aosp-build/actions/runs/31758099068) |
| Full uncached build, 96-vCPU machine only | 34m 07s | [31851206170](https://github.com/aspect-build/basic-aosp-build/actions/runs/31851206170) |
| Full uncached build, 512-slot remote fleet | **24m 38s** | [31847444276](https://github.com/aspect-build/basic-aosp-build/actions/runs/31847444276) |
| Incremental, nothing changed | 2m 38s | [31850749685](https://github.com/aspect-build/basic-aosp-build/actions/runs/31850749685) |

The remote run executed 81,463 of 81,481 dispatched actions on the fleet with zero
failures and zero cache hits (cache reuse deliberately disabled). On the parallelizable
part of the build, remote execution is 3.9x faster than 96 local vCPUs; the end-to-end
ratio is smaller because AOSP ends in a serial packaging tail no platform can parallelize.

## Repository layout

| File | Purpose |
|---|---|
| `build-aosp.sh` | Fetches the manifest, syncs source, runs the build. Works standalone with no RBE at all. |
| `rbe.sh` | The reclient configuration, sourced instead of plain `envsetup.sh` when `--rbe` is set. |
| `.github/workflows/aosp-build.yaml` | CI: runs the build on a self-hosted Aspect Workflows runner and uploads logs. |

## Local usage

```bash
./build-aosp.sh                                                 # AAOS arm64, android-17.0.0_r1
./build-aosp.sh -b android-16.0.0_r4                            # another branch
./build-aosp.sh -t aosp_cf_x86_64_auto-trunk_staging-userdebug  # another target
./build-aosp.sh -r                                              # with remote execution (see rbe.sh)
./build-aosp.sh -j 2                                            # fewer repo-sync jobs if AOSP's servers 429 you
./build-aosp.sh -d /mnt/fast/aosp                               # build directory on fast local disk
./build-aosp.sh -c                                              # clean: removes the build directory first
./build-aosp.sh -l                                              # list available lunch targets
```

Lunch targets take the three-part `<product>-<release>-<variant>` form on trunk-stable
branches; the two-part `aosp_arm64-userdebug` spelling is rejected outright on 17.

Requirements are AOSP's usual ones: Linux, plenty of cores, and disk. Budget ~200 GB for
the synced tree plus ~250 GB for `out/` on a full build, on local NVMe if at all possible.
`repo` is installed automatically if missing. One host package matters and is easy to
miss: AOSP's prebuilt bison spawns **`m4` from `PATH`** during parser generation, and
without it the build dies at ~35% with `m4 subprocess failed`.

The build log tees to `aosp-build.log` next to the build directory. Artifacts land in
`<build-dir>/out/target/product/*/`.

## CI

The workflow runs on a self-hosted runner labeled `aspect-aosp-demo` and is dispatchable
with:

| Input | Effect |
|---|---|
| `branch`, `target` | Passed through to `build-aosp.sh -b` / `-t` |
| `rbe` | Toggles `--rbe` |
| `clean` | Wipes the whole build directory, `.repo` included |
| `no_cache` | Cold-cache benchmark: drops `out/`, disables ccache, and refuses remote cache hits, so every action executes on a worker. Keeps the synced tree. |

Runners persist between builds (idle timeout), which is what makes the numbers above
possible: the first-ever run paid 39m 21s of cold `repo sync`; every warm run since pays
about 90 seconds. Each run uploads `aosp-build.log` and `rbe_logs.tar.gz`; the latter
contains `rbe_metrics.txt` (per-action completion statuses) and reclient's per-action
record log.

## How the RBE wiring works

Read `rbe.sh` alongside this; the comments there carry the details. The short version:

- **reclient talks to a local forwarder, not the cluster.** `RBE_service` points at
  bb_clientd's unix socket on the runner; bb_clientd handles the connection to the
  Workflows deployment, plus local caching.
- **`RBE_instance` must be empty.** The storage tier registers only the `""` instance
  name; anything else fails every request with `'instance_name' not configured`.
- **AOSP owns the action platform, not `rbe.sh`.** `build/make/core/rbe.mk` passes
  `--platform` on every rewrapper command line, with the container image digest hardcoded
  per AOSP branch and `Pool=$RBE_*_POOL` interpolated in. An `RBE_platform` export can't
  override an explicit flag, so the one in `rbe.sh` is documentation of what the build
  sends, not a setting.
- **The executor must advertise exactly what the action carries**: `Pool=aosp` plus that
  branch's `container-image` digest, and nothing more, because Buildbarn matches the property
  set exactly, so an extra `OSFamily` means nothing schedules. Changing the AOSP branch
  changes the digest in rbe.mk, and the executor config has to follow. Re-derive it with:

  ```bash
  grep -o 'docker://[^,"]*' build/make/core/rbe.mk
  ```

- **Set every `RBE_*_POOL`.** rbe.mk defaults `RBE_JAVA_POOL` to `java16`; any tool whose
  pool no executor advertises becomes unschedulable, silently, because every tool is
  configured `remote_local_fallback`.
- **`NINJA_REMOTE_NUM_JOBS` is sized to the fleet** (800 in flight against 512 slots).
  Scale the two together: in-flight actions include queue and transfer time, so the
  pipeline must run deeper than the slot count to keep the slots busy.
- **The cache bypass is `RBE_remote_accept_cache`, with no trailing "d".** The misspelled
  variant isn't a flag and is ignored in silence; ours was misspelled for a while and
  produced a very convincing 8-minute "cold" build that was 99.98% cache hits.

The matching fleet configuration (worker instance type, per-action memory ceiling,
concurrency, and the placement arithmetic that ties them together) lives in the Workflows
deployment's terraform, not in this repo.

## Failure modes worth knowing

- **RBE failures are silent by design.** Every tool falls back to local execution, so a
  dead platform match, a wrong instance name, or a missing pool looks like a slow build,
  not an error. The quick check on the runner:

  ```bash
  grep -c "Executing remotely" <build-dir>/out/soong/.temp/rbe/reproxy.INFO
  ```

  Zero a few minutes into ninja means nothing is going remote; `rbe_metrics.txt` at build
  end has the authoritative remote/local/cache split.
- **`repo sync` 429s**: the script defaults to 4 sync jobs and retries with fewer; `-j 2`
  or `-j 1` if AOSP's servers are rate-limiting you.
- **Missing `m4`**: see above; install it on the host or bake it into the runner image.
