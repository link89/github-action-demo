#!/usr/bin/env python3
"""Load a DeePMD model through the C API used by CP2K.

Run this inside a CP2K image, for example:

    apptainer run --nv --bind "$PWD:/work" --pwd /work \
        cp2k.sif python scripts/debug-cp2k-dp.py model.pt2

CP2K reports only the beginning of the DeePMD error because its Fortran
wrapper copies the message into a fixed-length string. This helper calls
DP_NewDeepPot() and DP_DeepPotCheckOK() directly and prints the complete
error without truncation.
"""

from __future__ import annotations

import argparse
import ctypes
import os
from pathlib import Path
import sys
from typing import Iterable


DEFAULT_DEEPMD_LIB = Path("/usr/local/lib/libdeepmd_c.so")
DEFAULT_PLUGIN = Path("/usr/local/lib/libdeepmd_backend_ptexpt.so")
REEXEC_MARKER = "CP2K_DP_DEBUG_REEXEC"

TORCH_PRELOAD_LIBS = (
    "libc10.so",
    "libtorch_cpu.so",
    "libc10_cuda.so",
    "libtorch_cuda.so",
    "libtorch.so",
    "libtorch_cuda_linalg.so",
    "libtorch_nvshmem.so",
)


def unique_paths(paths: Iterable[Path]) -> list[Path]:
    result: list[Path] = []
    seen: set[Path] = set()
    for path in paths:
        normalized = path.absolute()
        if normalized not in seen:
            seen.add(normalized)
            result.append(normalized)
    return result


def find_torch_lib(explicit: Path | None) -> Path | None:
    candidates: list[Path] = []
    for value in (explicit, os.environ.get("CP2K_TORCH_LIB")):
        if value:
            candidates.append(Path(value))

    roots = (Path("/usr/local/lib"), Path("/usr/lib"), Path("/opt/conda/lib"))
    for root in roots:
        if not root.is_dir():
            continue
        for pattern in (
            "python*/site-packages/torch/lib",
            "python*/dist-packages/torch/lib",
        ):
            candidates.extend(sorted(root.glob(pattern)))

    for entry in sys.path:
        if entry:
            candidates.append(Path(entry) / "torch" / "lib")

    for candidate in unique_paths(candidates):
        if (candidate / "libc10.so").is_file() and (
            candidate / "libtorch_cpu.so"
        ).is_file():
            return candidate
    return None


def find_deepmd_lib(explicit: Path | None) -> Path | None:
    candidates: list[Path] = []
    for value in (explicit, os.environ.get("DEEPMD_C_LIB"), DEFAULT_DEEPMD_LIB):
        if value:
            candidates.append(Path(value))
    candidates.extend(
        sorted(Path("/usr/local/lib").glob("libdeepmd_c.so*"))
    )
    for candidate in unique_paths(candidates):
        if candidate.is_file():
            return candidate
    return None


def find_plugin(explicit: Path | None) -> Path | None:
    candidates: list[Path] = []
    for value in (explicit, os.environ.get("DEEPMD_PTEXPT_PLUGIN"), DEFAULT_PLUGIN):
        if value:
            candidates.append(Path(value))

    plugin_path = os.environ.get("DP_BACKEND_PLUGIN_PATH", "")
    for directory in plugin_path.split(os.pathsep):
        if directory:
            candidates.append(
                Path(directory) / "libdeepmd_backend_ptexpt.so"
            )

    for candidate in unique_paths(candidates):
        if candidate.is_file():
            return candidate
    return None


def prepend_paths(paths: Iterable[Path], existing: str) -> str:
    values = [str(path) for path in unique_paths(paths)]
    if existing:
        values.extend(item for item in existing.split(os.pathsep) if item)
    return os.pathsep.join(dict.fromkeys(values))


def torch_preload_paths(torch_lib: Path) -> list[Path]:
    return [
        torch_lib / name
        for name in TORCH_PRELOAD_LIBS
        if (torch_lib / name).is_file()
    ]


def prepare_environment(
    torch_lib: Path,
    deepmd_lib: Path,
    plugin: Path | None,
) -> dict[str, str]:
    env = os.environ.copy()

    search_paths = [torch_lib, deepmd_lib.parent]
    if plugin is not None:
        search_paths.append(plugin.parent)
    search_paths.extend(
        path
        for path in (Path("/usr/local/cuda/lib64"), Path("/.singularity.d/libs"))
        if path.is_dir()
    )
    env["LD_LIBRARY_PATH"] = prepend_paths(
        search_paths, env.get("LD_LIBRARY_PATH", "")
    )

    preload = [str(path) for path in torch_preload_paths(torch_lib)]
    existing_preload = env.get("LD_PRELOAD", "")
    if existing_preload:
        preload.extend(
            item for item in existing_preload.split(os.pathsep) if item
        )
    if preload:
        env["LD_PRELOAD"] = os.pathsep.join(dict.fromkeys(preload))

    plugin_dirs = [deepmd_lib.parent]
    if plugin is not None:
        plugin_dirs.insert(0, plugin.parent)
    env["DP_BACKEND_PLUGIN_PATH"] = prepend_paths(
        plugin_dirs, env.get("DP_BACKEND_PLUGIN_PATH", "")
    )
    env[REEXEC_MARKER] = "1"
    return env


def format_path(path: Path | None) -> str:
    return str(path) if path is not None else "<not found>"


def print_header(
    model: Path,
    deepmd_lib: Path,
    torch_lib: Path | None,
    plugin: Path | None,
) -> None:
    print("== CP2K DeePMD model loader ==", flush=True)
    print(f"model: {model}")
    print(f"model size: {model.stat().st_size} bytes")
    print(f"python: {sys.executable}")
    print(f"libdeepmd_c: {deepmd_lib}")
    print(f"torch lib: {format_path(torch_lib)}")
    print(f"ptexpt plugin: {format_path(plugin)}")
    print("selected environment:")
    for name in (
        "LD_LIBRARY_PATH",
        "LD_PRELOAD",
        "DP_BACKEND_PLUGIN_PATH",
        "CUDA_VISIBLE_DEVICES",
        "NVIDIA_VISIBLE_DEVICES",
    ):
        print(f"  {name}={os.environ.get(name, '<unset>')}")


def print_mapped_libraries() -> None:
    maps = Path("/proc/self/maps")
    if not maps.is_file():
        return

    prefixes = ("libc10", "libtorch", "libcuda", "libdeepmd")
    libraries: list[str] = []
    for line in maps.read_text(errors="replace").splitlines():
        for field in line.split():
            if field.startswith("/") and Path(field).name.startswith(prefixes):
                if field not in libraries:
                    libraries.append(field)
    if libraries:
        print("loaded runtime libraries:")
        for library in libraries:
            print(f"  {library}")


def probe_cuda() -> None:
    mode = getattr(os, "RTLD_NOW", 2) | getattr(os, "RTLD_GLOBAL", 0x100)
    try:
        ctypes.CDLL("libcuda.so.1", mode=mode)
    except OSError as exc:
        print("CUDA driver preflight: FAILED", flush=True)
        print(f"libcuda.so.1: {exc}", flush=True)
    else:
        print("CUDA driver preflight: OK", flush=True)


def load_model(model: Path, deepmd_lib: Path) -> int:
    mode = getattr(os, "RTLD_NOW", 2) | getattr(os, "RTLD_GLOBAL", 0x100)
    try:
        library = ctypes.CDLL(str(deepmd_lib), mode=mode)
    except OSError as exc:
        print("Unable to load libdeepmd_c:", flush=True)
        print(str(exc), flush=True)
        return 1

    try:
        new_deep_pot = library.DP_NewDeepPot
        check_ok = library.DP_DeepPotCheckOK
    except AttributeError as exc:
        print("libdeepmd_c does not expose the required C API:", flush=True)
        print(str(exc), flush=True)
        return 1

    new_deep_pot.argtypes = [ctypes.c_char_p]
    new_deep_pot.restype = ctypes.c_void_p
    check_ok.argtypes = [ctypes.c_void_p]
    # Keep the returned pointer opaque. ctypes must not copy or free it.
    check_ok.restype = ctypes.c_void_p

    print(f"Calling DP_NewDeepPot({model})", flush=True)
    model_handle = new_deep_pot(os.fsencode(model))
    if not model_handle:
        print("DP_NewDeepPot returned NULL", flush=True)
        return 1

    error_ptr = check_ok(model_handle)
    if not error_ptr:
        print("DP_DeepPotCheckOK returned NULL", flush=True)
        return 1

    error = ctypes.string_at(error_ptr).decode("utf-8", errors="replace")
    if error:
        print("", flush=True)
        print("=" * 78)
        print("FULL DeePMD ERROR (untruncated):")
        print(error)
        print("=" * 78, flush=True)
        # Failed model initialization has crashed during cleanup in some
        # mixed-libtorch images. Exit directly after flushing the real error.
        print(
            "Skipping DeePMD cleanup so the original error is not obscured.",
            flush=True,
        )
        print_mapped_libraries()
        return 1

    print("Model loaded successfully.", flush=True)
    print_mapped_libraries()
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Load a model through the same DeePMD C API used by CP2K and "
            "print the complete, untruncated error."
        )
    )
    parser.add_argument("model", type=Path, help="Path to a .pt2, .pt, or .pb model")
    parser.add_argument(
        "--deepmd-lib",
        type=Path,
        help=f"libdeepmd_c path (default: auto-detect, usually {DEFAULT_DEEPMD_LIB})",
    )
    parser.add_argument(
        "--torch-lib",
        type=Path,
        help="PyTorch library directory (default: auto-detect)",
    )
    parser.add_argument(
        "--plugin",
        type=Path,
        help=f"PyTorch Exportable plugin path (default: {DEFAULT_PLUGIN})",
    )
    parser.add_argument(
        "--keep-env",
        action="store_true",
        help="Use the current dynamic-loader environment without re-exec",
    )
    args = parser.parse_args()

    model = args.model.absolute()
    if not model.is_file():
        parser.error(f"model file not found: {model}")

    deepmd_lib = find_deepmd_lib(args.deepmd_lib)
    if deepmd_lib is None:
        parser.error(
            "libdeepmd_c.so not found; set --deepmd-lib or DEEPMD_C_LIB"
        )

    plugin = find_plugin(args.plugin)
    torch_lib = find_torch_lib(args.torch_lib)

    if not args.keep_env and os.environ.get(REEXEC_MARKER) != "1":
        if torch_lib is None:
            parser.error(
                "PyTorch library directory not found; set --torch-lib or "
                "use --keep-env"
            )
        env = prepare_environment(torch_lib, deepmd_lib, plugin)
        script = Path(__file__).resolve()
        os.execve(
            sys.executable,
            [sys.executable, str(script), *sys.argv[1:]],
            env,
        )

    print_header(model, deepmd_lib, torch_lib, plugin)
    print_mapped_libraries()
    probe_cuda()
    return load_model(model, deepmd_lib)


if __name__ == "__main__":
    result = main()
    sys.stdout.flush()
    sys.stderr.flush()
    # This one-shot diagnostic process deliberately skips interpreter teardown
    # and DeePMD object cleanup, which have crashed after failed model loads.
    os._exit(result)
