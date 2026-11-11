#!/usr/bin/env python3
"""Build an Apptainer SIF image from a remote Docker image."""

from __future__ import annotations

import argparse
from pathlib import Path
import shlex
import shutil
import subprocess
import sys


OCI_TAG = "latest"


def default_output(image: str) -> Path:
    image_name = image.rstrip("/").rsplit("/", 1)[-1]
    return Path(f"{image_name.replace(':', '-')}.sif")


def require_command(name: str) -> None:
    if shutil.which(name) is None:
        sys.exit(f"error: {name} is required")


def run(command: list[str]) -> None:
    print(f"+ {shlex.join(command)}", flush=True)
    subprocess.run(command, check=True)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Build an Apptainer SIF image from a remote Docker image."
    )
    parser.add_argument(
        "image",
        help="Docker image reference, e.g. ghcr.io/link89/cp2k:2026.2",
    )
    parser.add_argument(
        "output",
        nargs="?",
        type=Path,
        help="Output SIF path (default: image basename with ':' replaced by '-')",
    )
    parser.add_argument(
        "--oci-dir",
        type=Path,
        help="OCI layout directory (default: ./tmp-oci)",
    )
    args = parser.parse_args()

    require_command("apptainer")
    require_command("skopeo")

    image = args.image.removeprefix("docker://")
    source = f"docker://{image}"
    output = (args.output or default_output(image)).resolve()
    oci_dir = (args.oci_dir or Path.cwd() / "tmp-oci").resolve()

    output.parent.mkdir(parents=True, exist_ok=True)
    oci_dir.mkdir(parents=True, exist_ok=True)

    print(f"Image: {source}")
    print(f"Output: {output}")
    print(f"OCI layout: {oci_dir}")

    if (oci_dir / "index.json").is_file():
        print(f"Using existing OCI layout: {oci_dir}")
    else:
        run(
            [
                "skopeo",
                "copy",
                "--retry-times",
                "20",
                "--override-os",
                "linux",
                "--override-arch",
                "amd64",
                source,
                f"oci:{oci_dir}:{OCI_TAG}",
            ]
        )

    # The oci: transport treats everything after "oci:" as the layout path and
    # has no :tag suffix (unlike oci-archive:). A single-manifest layout is
    # selected automatically.
    run(["apptainer", "build", "--force", str(output), f"oci:{oci_dir}"])
    print(f"Created: {output}")


if __name__ == "__main__":
    main()
