source build/envsetup.sh
source build/make/rbesetup.sh  

export RBE_service="unix:///mnt/ephemeral/buildbarn/.cache/bb_clientd/grpc" 
export RBE_use_application_default_credentials="false" 
export RBE_use_rpc_credentials="false" 
  
export USE_RBE="1"
# Sized against the fleet: the aosp executor serves 512 slots (32 x 16, see
# deployments/staging/aws/gha-test/workflows.tf), and in-flight actions include queue and
# transfer time, not just execution -- so keeping ~800 in flight is what holds 512 slots
# busy. Scale the two together.
export NINJA_REMOTE_NUM_JOBS="800"
# Feeds the RBE_*_POOL vars below. build/make/core/rbe.mk interpolates those into the
# `--platform=...,Pool=<pool>` flag it passes to rewrapper, so `Pool` (capital P) lands on
# every action even though it appears in no RBE_platform value. The `aosp` executor in
# silo-solo (deployments/prod/aws/silo and deployments/staging/aws/gha-test) advertises
# Pool=aosp to match, so changing this value here requires the same change there.
#
# Every tool needs its own RBE_*_POOL: rbe.mk defaults RBE_CXX_POOL to "default" and
# RBE_JAVA_POOL to "java16", and a pool no executor advertises makes those actions
# unschedulable.
export WORKER_POOL="aosp"
 
export RBE_ABI_DUMPER="1" 
export RBE_ABI_DUMPER_EXEC_STRATEGY="remote_local_fallback" 
export RBE_ABI_DUMPER_POOL="$WORKER_POOL" 
export RBE_ABI_LINKER="1" 
export RBE_ABI_LINKER_EXEC_STRATEGY="remote_local_fallback" 
export RBE_ABI_LINKER_POOL="$WORKER_POOL" 
export RBE_CLANG_TIDY="1" 
export RBE_CLANG_TIDY_EXEC_STRATEGY="remote_local_fallback" 
export RBE_CLANG_TIDY_POOL="$WORKER_POOL" 
export RBE_CXX="1" 
export RBE_CXX_EXEC_STRATEGY="remote_local_fallback" 
export RBE_CXX_POOL="$WORKER_POOL" 
export RBE_CXX_LINKS="1" # changed from 0 
export RBE_CXX_LINKS_EXEC_STRATEGY="remote_local_fallback"
export RBE_CXX_LINKS_STRATEGY="remote_local_fallback"
export RBE_CXX_LINKS_POOL="$WORKER_POOL"
export RBE_D8="1" 
export RBE_D8_EXEC_STRATEGY="remote_local_fallback" 
export RBE_D8_POOL="$WORKER_POOL" 
export RBE_JAR="1" 
export RBE_JAR_EXEC_STRATEGY="remote_local_fallback" 
export RBE_JAR_POOL="$WORKER_POOL" 
export RBE_JAVA="1" 
export RBE_JAVA_POOL="$WORKER_POOL" 
export RBE_JAVAC="1" 
export RBE_JAVAC_EXEC_STRATEGY="remote_local_fallback" 
export RBE_JAVAC_POOL="$WORKER_POOL" 
export RBE_METALAVA="0" 
export RBE_METALAVA_POOL="$WORKER_POOL" 
export RBE_R8="1" 
export RBE_R8_EXEC_STRATEGY="remote_local_fallback" 
export RBE_R8_POOL="$WORKER_POOL" 
export RBE_SIGNAPK="1" 
export RBE_SIGNAPK_EXEC_STRATEGY="remote_local_fallback" 
export RBE_SIGNAPK_POOL="$WORKER_POOL" 
export RBE_TURBINE="1" 
export RBE_TURBINE_EXEC_STRATEGY="remote_local_fallback" 
export RBE_TURBINE_POOL="$WORKER_POOL" 
export RBE_ZIP="1" 
export RBE_ZIP_EXEC_STRATEGY="remote_local_fallback" 
export RBE_ZIP_POOL="$WORKER_POOL" 
 
# Empty on purpose: bb_clientd routes by instance name and registers only '' (see
# schedulers/blobstore in infrastructure/modules/workflows/runners/bbclientd/bb_clientd.jsonnet).
# Anything else fails with "'instance_name' not configured".
export RBE_instance=""
export RBE_DIR="prebuilts/remoteexecution-client/live" 
export RBE_server_address="unix:///mnt/ephemeral/buildbarn/.cache/bb_clientd/grpc" 
# Note the name: rewrapper's flag is `remote_accept_cache`, with no trailing "d". An
# RBE_remote_accept_cached export is not a flag at all and is silently ignored, so a
# cold-cache benchmark set that way still takes every cache hit.
#
# Overridable so such a benchmark can set it to false, which skips the GetActionResult
# lookup entirely -- bypassing bb_clientd's local cache as well as the cluster's -- and
# sends every action to a worker. Do not reach for RBE_cache_silo instead: that busts the
# cache by adding a platform property, which stops matching the executor's advertised set
# and sends the build local rather than remote.
export RBE_remote_accept_cache="${RBE_remote_accept_cache:-true}"
export RBE_service_no_auth="true" 
 
export RBE_enable_deps_cache="true" 
export RBE_cache_dir="$HOME/.cache/reclient/cache" 
mkdir -p $RBE_cache_dir 
# Inert, and kept only to document what the build actually sends. build/make/core/rbe.mk
# passes `--platform` on every rewrapper command line -- image digest hardcoded there,
# plus `Pool=$RBE_CXX_POOL` (or `$RBE_JAVA_POOL` for the java tools) -- and an explicit
# flag beats the environment. So the digest below is not a setting; it is a copy of the
# one in that branch's rbe.mk, and it moves when the AOSP branch moves.
export RBE_platform="container-image=docker://gcr.io/androidbuild-re-dockerimage/android-build-remoteexec-image@sha256:582efb38f0c229ea39952fff9e132ccbe183e14869b39888010dacf56b360d62"
export RBE_v=4
export RBE_alsologtostderr=true 
export RBE_service_no_security=true 
# OPTIONAL: Skip downloading object files. 
# export RBE_download_regex="-.*\\.o" 
