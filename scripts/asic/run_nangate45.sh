#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
requested_build_directory=${BUILD_DIR:-"$project_root/build/asic-nangate45"}
build_directory=$(realpath -m "$requested_build_directory")
stage=${1:-finish}
flow_variant=${FLOW_VARIANT:-baseline}
asic_design=${ASIC_DESIGN:-chip}
docker_image="openroad/orfs@sha256:73bd87efa06758865277f347fbc6b932642d8ab21a5430c5ce5480aaa60c27d0"

case "$stage" in
    synth|floorplan|place|cts|route|finish) ;;
    *)
        echo "ERROR: stage must be synth, floorplan, place, cts, route, or finish" >&2
        exit 1
        ;;
esac

case "$asic_design" in
    core)
        design_config=/work/config/asic/z8086_core_nangate45.mk
        design_name=z8086
        ;;
    chip)
        design_config=/work/config/asic/z8086_chip_nangate45.mk
        design_name=z8086_chip
        ;;
    external_chip)
        design_config=/work/config/asic/z8086_external_chip_nangate45.mk
        design_name=z8086_external_chip_core
        ;;
    *)
        echo "ERROR: ASIC_DESIGN must be core, chip, or external_chip" >&2
        exit 1
        ;;
esac

if [[ ! "$flow_variant" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
    echo "ERROR: FLOW_VARIANT must use lowercase letters, digits, underscores, or hyphens" >&2
    exit 1
fi

case "$build_directory" in
    "$project_root"/build/*) ;;
    *)
        echo "ERROR: ASIC output must be under $project_root/build" >&2
        exit 1
        ;;
esac

command -v docker >/dev/null || {
    echo "ERROR: Docker is required for the pinned ORFS flow" >&2
    exit 1
}

docker image inspect "$docker_image" >/dev/null 2>&1 || {
    echo "ERROR: required ORFS image is not available locally: $docker_image" >&2
    echo "Fetch it with: docker pull $docker_image" >&2
    exit 1
}

mkdir -p "$build_directory"
runtime_directory="$build_directory/.xdg-runtime"
mkdir -p "$runtime_directory"
chmod 700 "$runtime_directory"
export Z8086_CLOCK_PERIOD_NS=${Z8086_CLOCK_PERIOD_NS:-20.0}
export Z8086_EXTERNAL_DIE_AREA=${Z8086_EXTERNAL_DIE_AREA:-"0 0 220 220"}
export Z8086_EXTERNAL_CORE_AREA=${Z8086_EXTERNAL_CORE_AREA:-"20.14 21 199.88 200.2"}

orfs_target=$stage
result_directory="$build_directory/results/nangate45/$design_name/$flow_variant"
case "$stage" in
    synth) stage_result="$result_directory/1_synth.odb" ;;
    floorplan) stage_result="$result_directory/2_floorplan.odb" ;;
    place) stage_result="$result_directory/3_place.odb" ;;
    cts) stage_result="$result_directory/4_cts.odb" ;;
    route) stage_result="$result_directory/5_route.odb" ;;
    finish) stage_result="$result_directory/6_final.odb" ;;
esac

# ORFS does not track arbitrary configuration variables as Make dependencies.
# Re-run an explicitly requested stage when its output already exists instead
# of silently accepting a stale ODB after a physical-configuration change.
if [[ -s "$stage_result" && "$stage" != finish ]]; then
    orfs_target="do-$stage"
fi

orfs_targets=("$orfs_target")
if [[ "$stage" == finish && "$asic_design" == chip ]]; then
    # FakeRAM provides LEF/Liberty but no stream file.  Build a new variant
    # through route first, then run extraction/STA/IR without attempting an
    # invalid GDS merge.  Existing routed variants can resume at finish.
    if [[ -s "$result_directory/5_route.odb" ]]; then
        orfs_targets=(do-finish)
    else
        orfs_targets=(route do-finish)
    fi
fi

if [[ "$stage" == finish && "$asic_design" != chip && -s "$result_directory/5_route.odb" ]]; then
    # Refresh DEF/netlist/extraction from the already signed-off route, then
    # build the real standard-cell GDS. This also prevents an idempotently
    # regenerated physical-only IO LEF from forcing a second detailed route.
    # The repository performs its own dimension-preserving GDS merge below;
    # only the KLayout technology object is needed from ORFS. Avoid the generic
    # `finish` dependency traversal, which treats a regenerated placeholder LEF
    # as an electrical change and needlessly invalidates a proven route.
    orfs_targets=(do-finish do-klayout_tech do-klayout)
fi

docker run --rm --network none --user "$(id -u):$(id -g)" \
    --mount "type=bind,src=$project_root,dst=/work,readonly" \
    --mount "type=bind,src=$build_directory,dst=/output" \
    --mount "type=bind,src=$project_root/scripts/asic/orfs/global_place.tcl,dst=/OpenROAD-flow-scripts/flow/scripts/global_place.tcl,readonly" \
    --mount "type=bind,src=$project_root/scripts/asic/orfs/final_outputs.tcl,dst=/OpenROAD-flow-scripts/flow/scripts/final_outputs.tcl,readonly" \
    --env Z8086_CLOCK_PERIOD_NS \
    --env Z8086_EXTERNAL_DIE_AREA \
    --env Z8086_EXTERNAL_CORE_AREA \
    --env XDG_RUNTIME_DIR=/output/.xdg-runtime \
    "$docker_image" \
    make -C /OpenROAD-flow-scripts/flow --no-print-directory \
        DESIGN_CONFIG="$design_config" \
        KLAYOUT_TECH_FILE=/work/config/asic/nangate45/FreePDK45_2000.lyt \
        WORK_HOME=/output \
        FLOW_VARIANT="$flow_variant" \
        "${orfs_targets[@]}"

log_directory="$build_directory/logs/nangate45/$design_name/$flow_variant"
"$project_root/scripts/asic/check_warning_free.sh" "$log_directory"

if [[ "$stage" == finish && "$asic_design" != chip ]]; then
    # ORFS' generic def2stream imports the 0.1 nm Nangate library into a
    # 0.5 nm DEF layout by retaining integer coordinates, then writes a 1 nm
    # GDS.  That silently scales masters by 10x and the DEF by 2x.  Rebuild the
    # stream through physical D* coordinates and read it back before accepting
    # it as the final GDS.  The ODB/DEF/routing are not modified.
    generated_tech="/output/objects/nangate45/$design_name/$flow_variant/klayout.lyt"
    final_def="/output/results/nangate45/$design_name/$flow_variant/6_final.def"
    normalized_gds="/output/results/nangate45/$design_name/$flow_variant/6_final_physical.gds"
    final_gds="$result_directory/6_final.gds"
    physical_inputs=/OpenROAD-flow-scripts/flow/platforms/nangate45/gds/NangateOpenCellLibrary.gds
    expected_die_size=220
    if [[ "$asic_design" == external_chip ]]; then
        physical_inputs+=" /work/build/asic-placeholder-ip/z8086_placeholder_io.gds"
        expected_die_size=1000
    fi

    merge_output=$(docker run --rm --network none --user "$(id -u):$(id -g)" \
        --env QT_QPA_PLATFORM=offscreen \
        --mount "type=bind,src=$project_root,dst=/work,readonly" \
        --mount "type=bind,src=$build_directory,dst=/output" \
        "$docker_image" klayout -b \
            -r /work/scripts/asic/merge_gds_physical.rb \
            -rd tech_file="$generated_tech" \
            -rd def_file="$final_def" \
            -rd design_name="$design_name" \
            -rd input_files="$physical_inputs" \
            -rd output_file="$normalized_gds" \
            -rd expected_die_size="$expected_die_size" 2>&1) || {
        echo "$merge_output" >&2
        echo "ERROR: dimension-preserving GDS merge failed" >&2
        exit 1
    }
    if [[ "$merge_output" == *Warning* || "$merge_output" == *WARNING* || \
          "$merge_output" == *Error* || "$merge_output" == *ERROR* ]]; then
        echo "$merge_output" >&2
        echo "ERROR: dimension-preserving GDS merge emitted diagnostics" >&2
        exit 1
    fi
    echo "$merge_output"
    mv "$build_directory/results/nangate45/$design_name/$flow_variant/6_final_physical.gds" \
       "$final_gds"
fi

case "$stage" in
    synth) expected_result="$result_directory/1_synth.odb" ;;
    floorplan) expected_result="$result_directory/2_floorplan.odb" ;;
    place) expected_result="$result_directory/3_place.odb" ;;
    cts) expected_result="$result_directory/4_cts.odb" ;;
    route) expected_result="$result_directory/5_route.odb" ;;
    finish) expected_result="$result_directory/6_final.odb" ;;
esac

if [[ ! -s "$expected_result" ]]; then
    echo "ERROR: ORFS did not produce $expected_result" >&2
    exit 1
fi

if [[ "$stage" == finish ]]; then
    final_report="$build_directory/reports/nangate45/$design_name/$flow_variant/6_finish.rpt"
    "$project_root/scripts/asic/check_final_signoff.sh" "$final_report"
fi

echo "PASS: warning-free Nangate45 $stage for $design_name"
echo "clock target: $Z8086_CLOCK_PERIOD_NS ns"
echo "result:       $expected_result"
