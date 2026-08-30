#!/usr/bin/env bash
# Friday Linux — SPEC.md §6 ("Inference"), §14 (build/build-llama.sh).
#
# Builds llama-server (Vulkan backend) plus llama-quantize and
# llama-gguf-split from the tag/commit pinned in build/llama.cpp.pin, run as
# a separate Containerfile build stage (see the "llama-build" stage there)
# so none of the compiler toolchain or llama.cpp source tree ends up in the
# shipped image — only the resulting binaries are COPYed into the final
# stage.
#
# M0 needs the Vulkan build only (SPEC.md §15: "llama-server-vulkan only,
# no GPU"). The CUDA build (§6, `llama-server-cuda`) is M2 scope and not
# built here — a separate build-llama-cuda step (a different builder base
# image with the CUDA toolkit) is deferred to that milestone.
#
# UNVERIFIED, flagged per SPEC.md §18 rule 5 rather than guessed silently:
# the exact Fedora package names for the Vulkan headers/loader/shader-
# compiler this build needs (vulkan-headers, vulkan-loader-devel, glslc vs.
# shaderc/glslang) have not been confirmed against Fedora 44's repos from
# inside this sandbox. This script's dnf install list in the Containerfile's
# "llama-build" stage is a best-effort reading of llama.cpp's own Vulkan
# build docs; if a package name is wrong, CI's dnf install step reports it
# and the fix is recorded in docs/DECISIONS.md, per rule 3/5 — not guessed
# twice.

set -euo pipefail

PIN_FILE="${1:-/tmp/llama.cpp.pin}"
OUT_DIR="${2:-/out}"
SRC_DIR="${3:-/tmp/llama.cpp}"

if [[ ! -f "$PIN_FILE" ]]; then
    echo "build-llama.sh: pin file not found at $PIN_FILE" >&2
    exit 1
fi

# build/llama.cpp.pin has the tag on the first non-comment line and the
# commit SHA (recorded per docs/VERIFY.md's instruction to pin both) on the
# second. Only the tag is needed for the clone; the commit is asserted
# against HEAD after clone as a tamper/drift check, per SPEC.md §18 rule 5
# ("never invent a version... use the most likely value, clearly marked").
mapfile -t PIN_LINES < <(grep -v '^#' "$PIN_FILE" | grep -v '^[[:space:]]*$')
LLAMA_TAG="${PIN_LINES[0]}"
LLAMA_COMMIT="${PIN_LINES[1]:-}"

echo "build-llama.sh: building ggml-org/llama.cpp @ ${LLAMA_TAG}"

git clone --branch "${LLAMA_TAG}" --depth 1 \
    https://github.com/ggml-org/llama.cpp.git "${SRC_DIR}"

if [[ -n "${LLAMA_COMMIT}" ]]; then
    ACTUAL_COMMIT="$(git -C "${SRC_DIR}" rev-parse HEAD)"
    if [[ "${ACTUAL_COMMIT}" != "${LLAMA_COMMIT}" ]]; then
        echo "build-llama.sh: WARNING — tag ${LLAMA_TAG} resolved to" \
             "${ACTUAL_COMMIT}, not the pinned ${LLAMA_COMMIT}." \
             "The tag may have moved. Continuing with the tag's current" \
             "commit rather than failing the build, since a moved release" \
             "tag on an upstream repo is not something this repo controls" \
             "— recorded here rather than silently ignored." >&2
    fi
fi

# BUILD_SHARED_LIBS=OFF matters here: CMake's default for this project
# links llama-server/-quantize/-gguf-split against shared libraries built
# alongside them (libllama-server-impl.so, libllama.so, libggml*.so,
# libggml-vulkan.so, etc. — confirmed by CI run 33320543663's build log,
# "Linking CXX shared library ../../bin/libllama-server-impl.so"). Copying
# only the executables (as this script did on its first pass) into the
# final image would ship a binary that fails at runtime with a missing
# shared-library error the first time anyone actually runs it — nothing in
# `podman build` executes the binary, so that bug would not show up until
# real boot testing, which is exactly the kind of "looks done, was never
# run" trap SPEC.md's rules warn about. Static linking keeps this a single
# self-contained binary per SPEC.md §14's plan
# (`/usr/libexec/friday/llama-server-vulkan`, one file, no lib directory to
# manage or set an RPATH/LD_LIBRARY_PATH for).
cmake -S "${SRC_DIR}" -B "${SRC_DIR}/build" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DGGML_VULKAN=ON \
    -DGGML_NATIVE=OFF \
    -DLLAMA_BUILD_TESTS=OFF \
    -DLLAMA_BUILD_EXAMPLES=OFF

cmake --build "${SRC_DIR}/build" --config Release \
    --target llama-server llama-quantize llama-gguf-split \
    -j"$(nproc)"

mkdir -p "${OUT_DIR}"
cp "${SRC_DIR}/build/bin/llama-server"      "${OUT_DIR}/llama-server-vulkan"
cp "${SRC_DIR}/build/bin/llama-quantize"    "${OUT_DIR}/llama-quantize"
cp "${SRC_DIR}/build/bin/llama-gguf-split"  "${OUT_DIR}/llama-gguf-split"

echo "build-llama.sh: done, binaries in ${OUT_DIR}"
ls -la "${OUT_DIR}"

# Verify the binaries are actually self-contained now, rather than trusting
# BUILD_SHARED_LIBS=OFF blindly: fail the build loudly if ldd still finds a
# dependency on one of this project's own shared libraries (libllama*,
# libggml*) or reports anything "not found". A missing *system* library
# (vulkan loader, libc, libstdc++, OpenMP) is expected and fine — those ship
# in the runtime image's dnf install list already.
echo "build-llama.sh: verifying static linking with ldd"
for bin in llama-server-vulkan llama-quantize llama-gguf-split; do
    echo "--- ldd ${OUT_DIR}/${bin} ---"
    ldd "${OUT_DIR}/${bin}"
    if ldd "${OUT_DIR}/${bin}" | grep -Ei 'libllama|libggml|not found'; then
        echo "build-llama.sh: ${bin} still depends on a project-local shared" \
             "library or is missing one — BUILD_SHARED_LIBS=OFF did not" \
             "fully take effect. Failing rather than shipping a binary that" \
             "would crash at runtime with a missing-library error." >&2
        exit 1
    fi
done
