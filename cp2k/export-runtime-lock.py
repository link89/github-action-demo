"""Export the runtime dependency closure from a jointly solved conda prefix."""

import json
from pathlib import Path
import re
import sys


def package_name(spec):
    return re.split(r"[\s=<>!~\[]", spec, maxsplit=1)[0]


def export(prefix, specs, output):
    records = {}
    for path in (prefix / "conda-meta").glob("*.json"):
        record = json.loads(path.read_text())
        records[record["name"]] = record
    pending = [
        package_name(line.strip())
        for line in specs.read_text().splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]
    selected = set()
    while pending:
        name = pending.pop()
        if name.startswith("__") or name in selected:
            continue
        if name not in records:
            raise RuntimeError(f"Missing solved dependency: {name}")
        selected.add(name)
        pending.extend(package_name(dep) for dep in records[name].get("depends", []))

    # OpenMPI is intentionally provided by conda-forge; reject competing MPI
    # implementations from the runtime dependency closure.
    conflicting_mpi = selected & {"mpich", "impi_rt", "intel-mpi"}
    if conflicting_mpi:
        raise RuntimeError(
            "Runtime packages selected conflicting MPI implementations: "
            + ", ".join(sorted(conflicting_mpi))
        )
    urls = []
    for name in sorted(selected):
        record = records[name]
        url = record["url"]
        if not url.startswith("https://conda.anaconda.org/conda-forge/"):
            raise RuntimeError(f"Unexpected package origin: {name}")
        urls.append(f"{url}#{record['md5']}")
    output.write_text("@EXPLICIT\n" + "\n".join(urls) + "\n")
    print(f"Locked {len(selected)} runtime packages from {len(records)} build packages")


if __name__ == "__main__":
    export(*(Path(arg) for arg in sys.argv[1:]))
