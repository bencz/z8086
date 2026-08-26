#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
flow_variant=${FLOW_VARIANT:-prefix_compact_1p5ns}
asic_design=${ASIC_DESIGN:-core}
docker_image="openroad/orfs@sha256:73bd87efa06758865277f347fbc6b932642d8ab21a5430c5ce5480aaa60c27d0"

case "$asic_design" in
    core)
        gds_relative="build/asic-nangate45-external/results/nangate45/z8086/$flow_variant/6_final.gds"
        image_name=z8086_die_photo.png
        default_output="$project_root/doc/z8086_die_photo.png"
        ;;
    external_chip)
        gds_relative="build/asic-nangate45-external-chip/results/nangate45/z8086_external_chip_core/$flow_variant/6_final.gds"
        image_name=z8086_tapeout_die.png
        default_output="$project_root/doc/z8086_tapeout_die.png"
        ;;
    *)
        echo "ERROR: ASIC_DESIGN must be core or external_chip" >&2
        exit 1
        ;;
esac

gds_file="$project_root/$gds_relative"
preview_directory="$project_root/build/asic-die-photo/$asic_design/$flow_variant"
raw_image="$preview_directory/$image_name"
output_image=${ASIC_DIE_IMAGE:-"$default_output"}

case "$output_image" in
    "$project_root"/doc/*) ;;
    *)
        echo "ERROR: ASIC_DIE_IMAGE must be under $project_root/doc" >&2
        exit 1
        ;;
esac

if [[ ! -s "$gds_file" ]]; then
    echo "ERROR: missing signed-off GDS: $gds_file" >&2
    exit 1
fi
command -v docker >/dev/null || {
    echo "ERROR: Docker is required for the pinned KLayout renderer" >&2
    exit 1
}
command -v magick >/dev/null || {
    echo "ERROR: ImageMagick 'magick' is required for PNG normalization" >&2
    exit 1
}
docker image inspect "$docker_image" >/dev/null 2>&1 || {
    echo "ERROR: required ORFS image is not available locally: $docker_image" >&2
    exit 1
}

mkdir -p "$preview_directory" "$(dirname "$output_image")"

if [[ "$asic_design" == external_chip ]]; then
    readable_directory="$preview_directory/readable"
    architecture_image="$project_root/build/asic-nangate45-external-chip/reports/nangate45/z8086_external_chip_core/$flow_variant/final_cpu_architecture.webp"
    mkdir -p "$readable_directory"
    if [[ ! -s "$architecture_image" ]]; then
        echo "ERROR: missing final ODB architecture image: $architecture_image" >&2
        exit 1
    fi

    klayout_output=$(docker run --rm --network none --user "$(id -u):$(id -g)" \
        --env QT_QPA_PLATFORM=offscreen \
        --mount "type=bind,src=$project_root,dst=/work,readonly" \
        --mount "type=bind,src=$readable_directory,dst=/preview" \
        "$docker_image" klayout -b \
            -r /work/scripts/asic/klayout_capture_die_suite.rb \
            -rd input="/work/$gds_relative" \
            -rd output_directory=/preview \
            -rd overall_properties=/work/config/asic/nangate45/z8086_die_overall.lyp \
            -rd device_properties=/work/config/asic/nangate45/z8086_core_devices.lyp \
            -rd routing_properties=/work/config/asic/nangate45/z8086_core_routing.lyp \
            -rd image_size=2000 2>&1) || {
        echo "$klayout_output" >&2
        echo "ERROR: KLayout failed to capture the physical die views" >&2
        exit 1
    }
    if [[ -n "$klayout_output" ]]; then
        echo "$klayout_output" >&2
        echo "ERROR: KLayout physical capture emitted diagnostic output" >&2
        exit 1
    fi

    die_full="$readable_directory/die_full_gds.png"
    core_devices="$readable_directory/core_devices_gds.png"
    core_routing="$readable_directory/core_routing_gds.png"
    for captured_image in "$die_full" "$core_devices" "$core_routing"; do
        if [[ ! -s "$captured_image" ]]; then
            echo "ERROR: missing physical capture: $captured_image" >&2
            exit 1
        fi
    done

    # Make one die-oriented image instead of a grid of unrelated technical
    # screenshots. The large view combines real device and routing geometry
    # from GDS with actual functional-cell highlights from the final ODB.
    # Boxes identify the placement-guide coordinates; the coloured individual
    # cells remain the authoritative record of where timing-driven placement
    # finally put each function.
    core_physical="$readable_directory/core_physical.png"
    # Functional cells are the primary readable geometry. Device and routing
    # captures remain visible as real GDS context, but are deliberately dimmed
    # so dense metal does not bleach every architectural colour into white.
    composite_output=$(magick "$architecture_image" -resize '2200x2200!' \
        -modulate 115,135,100 \
        \( "$core_devices" -resize '2200x2200!' -modulate 65,70,100 \
           -alpha set -channel A -evaluate multiply 0.32 +channel \) \
        -compose screen -composite \
        \( "$core_routing" -resize '2200x2200!' -modulate 35,50,100 \
           -alpha set -channel A -evaluate multiply 0.14 +channel \) \
        -compose screen -composite "$core_physical" 2>&1) || {
        echo "$composite_output" >&2
        echo "ERROR: failed to combine final GDS and ODB core geometry" >&2
        exit 1
    }
    if [[ -n "$composite_output" || ! -s "$core_physical" ]]; then
        echo "$composite_output" >&2
        echo "ERROR: physical core composition emitted diagnostics" >&2
        exit 1
    fi

    annotated_core="$readable_directory/core_annotated.png"
    annotation_output=$(magick "$core_physical" \
        -font Helvetica -gravity northwest \
        -stroke '#27d7ff' -strokewidth 6 -fill '#27d7ff18' \
        -draw 'rectangle 110,183 623,1100' \
        -stroke '#32d26f' -fill '#32d26f18' \
        -draw 'rectangle 697,183 1100,1100' \
        -stroke '#239447' -fill '#23944718' \
        -draw 'rectangle 1173,183 1503,1100' \
        -stroke '#ff4b3e' -fill '#ff4b3e18' \
        -draw 'rectangle 1577,183 2090,1100' \
        -stroke '#ffe33d' -fill '#ffe33d18' \
        -draw 'rectangle 110,1173 660,2017' \
        -stroke '#b8c2d8' -strokewidth 3 -fill '#b8c2d810' \
        -draw 'rectangle 733,1173 1210,2017' \
        -stroke '#ec48e8' -strokewidth 6 -fill '#ec48e818' \
        -draw 'rectangle 1283,1173 2090,2017' \
        -stroke none -fill '#07101ddd' \
        -draw 'rectangle 126,199 607,286 rectangle 713,199 1084,286 rectangle 1189,199 1487,286 rectangle 1593,199 2074,286 rectangle 126,1189 644,1276 rectangle 749,1189 1194,1311 rectangle 1299,1189 2074,1276' \
        -fill '#27d7ff' -pointsize 32 -annotate +148+220 'MICROCODE ROM' \
        -fill '#a9bed0' -pointsize 22 -annotate +148+258 '512 x 21-bit gate ROM' \
        -fill '#32d26f' -pointsize 27 -annotate +735+220 'FETCH / DECODER' \
        -fill '#239447' -pointsize 27 -annotate +1211+220 'CONTROL' \
        -fill '#ff4b3e' -pointsize 29 -annotate +1615+220 'BUS INTERFACE / BIU' \
        -fill '#ffe33d' -pointsize 32 -annotate +148+1210 'REGISTER BANK' \
        -fill '#d9e0ed' -pointsize 27 -annotate +771+1210 'SHARED / EXCHANGE' \
        -fill '#a9bed0' -pointsize 21 -annotate +771+1248 'cross-boundary logic' \
        -fill '#ec48e8' -pointsize 32 -annotate +1321+1210 'ALU / DATAPATH' \
        "$annotated_core" 2>&1) || {
        echo "$annotation_output" >&2
        echo "ERROR: failed to annotate the physical CPU regions" >&2
        exit 1
    }
    if [[ -n "$annotation_output" || ! -s "$annotated_core" ]]; then
        echo "$annotation_output" >&2
        echo "ERROR: physical CPU annotation emitted diagnostics" >&2
        exit 1
    fi

    final_output=$(magick -size 3600x2700 xc:'#080e1c' \
        "$annotated_core" -geometry +80+330 -composite \
        \( "$die_full" -resize '1000x1000!' -bordercolor '#5f708e' -border 4 \) \
        -geometry +2480+350 -composite \
        -font Helvetica -gravity northwest \
        -fill white -pointsize 70 -annotate +80+62 'z8086 — FINAL PHYSICAL DIE' \
        -fill '#9fb0c9' -pointsize 34 \
        -annotate +82+154 'External-memory variant | final routed GDS + final ODB | Nangate45' \
        -fill '#dce6f6' -pointsize 42 -annotate +2480+270 'FULL DIE — FINAL GDS' \
        -fill '#dce6f6' -pointsize 42 -annotate +2480+1440 'FUNCTIONAL COLOUR MAP' \
        -fill '#27d7ff' -pointsize 34 -annotate +2480+1520 '■  Microcode ROM' \
        -fill '#32d26f' -pointsize 34 -annotate +2480+1580 '■  Fetch and decoder' \
        -fill '#239447' -pointsize 34 -annotate +2480+1640 '■  Sequencer and control' \
        -fill '#ffe33d' -pointsize 34 -annotate +2480+1700 '■  Register bank' \
        -fill '#ec48e8' -pointsize 34 -annotate +2480+1760 '■  ALU and datapath' \
        -fill '#ff4b3e' -pointsize 34 -annotate +2480+1820 '■  Bus interface' \
        -fill '#b8c2d8' -pointsize 34 -annotate +2480+1880 '■  Shared exchange logic' \
        -fill '#dce6f6' -pointsize 42 -annotate +2480+1990 'PHYSICAL STATUS' \
        -fill '#aebbd0' -pointsize 31 \
        -annotate +2480+2070 'Die: 1000 x 1000 um' \
        -annotate +2480+2125 'Core rows: 319.77 x 313.60 um' \
        -annotate +2480+2180 'CPU partitions: 270 x 250 um' \
        -annotate +2480+2235 '48 evenly distributed I/O sites' \
        -annotate +2480+2290 'Post-route DRC: 0 | antenna: 0' \
        -fill '#f4bd62' -pointsize 28 \
        -annotate +2480+2370 'Open-PDK I/O objects are placement' \
        -annotate +2480+2415 'envelopes, not qualified pad / ESD IP.' \
        -fill '#71829e' -pointsize 26 \
        -annotate +2480+2480 'Boxes show architectural placement areas.' \
        -annotate +2480+2522 'Colours show actual post-route cells.' \
        -depth 8 -strip "$output_image" 2>&1) || {
        echo "$final_output" >&2
        echo "ERROR: failed to compose the annotated physical die image" >&2
        exit 1
    }
    if [[ -n "$final_output" || ! -s "$output_image" ]]; then
        echo "$final_output" >&2
        echo "ERROR: annotated physical die image emitted diagnostics" >&2
        exit 1
    fi

    echo "PASS: captured annotated physical die from final GDS and ODB"
    echo "design: $asic_design"
    echo "output: $output_image"
    exit 0
fi

klayout_output=$(docker run --rm --network none --user "$(id -u):$(id -g)" \
    --env QT_QPA_PLATFORM=offscreen \
    --mount "type=bind,src=$project_root,dst=/work,readonly" \
    --mount "type=bind,src=$preview_directory,dst=/preview" \
    "$docker_image" klayout -b \
        -r /work/scripts/asic/klayout_capture_die.rb \
        -rd input="/work/$gds_relative" \
        -rd output="/preview/$image_name" \
        -rd layer_properties=/work/config/asic/nangate45/z8086_die_photo.lyp \
        -rd image_size=1800 2>&1) || {
    echo "$klayout_output" >&2
    echo "ERROR: KLayout failed to capture the signed-off GDS" >&2
    exit 1
}
if [[ -n "$klayout_output" ]]; then
    echo "$klayout_output" >&2
    echo "ERROR: KLayout die capture emitted diagnostic output" >&2
    exit 1
fi
if [[ ! -s "$raw_image" ]]; then
    echo "ERROR: KLayout produced no die capture: $raw_image" >&2
    exit 1
fi

converter_output=$(magick "$raw_image" \
    -depth 8 -strip "$output_image" 2>&1) || {
    echo "$converter_output" >&2
    echo "ERROR: failed to normalize KLayout die capture" >&2
    exit 1
}
if [[ -n "$converter_output" ]]; then
    echo "$converter_output" >&2
    echo "ERROR: die capture normalization emitted diagnostic output" >&2
    exit 1
fi
if [[ ! -s "$output_image" ]]; then
    echo "ERROR: die overview produced an empty output: $output_image" >&2
    exit 1
fi

echo "PASS: captured warning-free die PNG directly from signed-off GDS"
echo "design: $asic_design"
echo "output: $output_image"
