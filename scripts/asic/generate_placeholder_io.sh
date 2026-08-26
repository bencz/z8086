#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
docker_image="openroad/orfs@sha256:73bd87efa06758865277f347fbc6b932642d8ab21a5430c5ce5480aaa60c27d0"
output_directory="$project_root/build/asic-placeholder-ip"
gds_file="$output_directory/z8086_placeholder_io.gds"
lef_file="$output_directory/z8086_placeholder_io.lef"

command -v docker >/dev/null || {
    echo "ERROR: Docker is required to generate placeholder physical IP" >&2
    exit 1
}
docker image inspect "$docker_image" >/dev/null 2>&1 || {
    echo "ERROR: required ORFS image is not available locally: $docker_image" >&2
    exit 1
}

mkdir -p "$output_directory"
generator_output=$(docker run --rm --network none --user "$(id -u):$(id -g)" \
    --env QT_QPA_PLATFORM=offscreen \
    --mount "type=bind,src=$project_root,dst=/work,readonly" \
    --mount "type=bind,src=$output_directory,dst=/output" \
    "$docker_image" klayout -b \
        -r /work/scripts/asic/generate_placeholder_io.rb \
        -rd gds_output=/output/z8086_placeholder_io.gds \
        -rd lef_output=/output/z8086_placeholder_io.lef 2>&1) || {
    echo "$generator_output" >&2
    echo "ERROR: failed to generate placeholder physical IP" >&2
    exit 1
}
if [[ -n "$generator_output" ]]; then
    echo "$generator_output" >&2
    echo "ERROR: placeholder physical-IP generator emitted diagnostic output" >&2
    exit 1
fi

if [[ ! -s "$gds_file" || ! -s "$lef_file" ]]; then
    echo "ERROR: placeholder physical-IP outputs are missing" >&2
    exit 1
fi

echo "PASS: generated process-replaceable IO/ESD placement envelopes"
echo "GDS: $gds_file"
echo "LEF: $lef_file"
