#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
requested_build_directory=${BUILD_DIR:-"$project_root/build/asic-nangate45"}
build_directory=$(realpath -m "$requested_build_directory")
flow_variant=${FLOW_VARIANT:-baseline}
asic_design=${ASIC_DESIGN:-chip}

case "$asic_design" in
    core) design_name=z8086 ;;
    chip) design_name=z8086_chip ;;
    external_chip) design_name=z8086_external_chip_core ;;
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
        echo "ERROR: ASIC input must be under $project_root/build" >&2
        exit 1
        ;;
esac

command -v magick >/dev/null || {
    echo "ERROR: ImageMagick 'magick' is required to render PNGs" >&2
    exit 1
}

report_directory="$build_directory/reports/nangate45/$design_name/$flow_variant"
output_directory="$build_directory/png/nangate45/$design_name/$flow_variant"
mkdir -p "$output_directory"

images=(
    cts_default_core_clock
    cts_default_core_clock_layout
    final_all
    final_cpu_architecture
    final_clocks
    final_congestion
    final_ir_drop
    final_placement
    final_resizer
    final_routing
    final_worst_path
)

for image_name in "${images[@]}"; do
    source_image="$report_directory/$image_name.webp"
    output_image="$output_directory/$image_name.png"
    if [[ ! -s "$source_image" ]]; then
        echo "ERROR: missing OpenROAD image: $source_image" >&2
        exit 1
    fi

    converter_output=$(magick "$source_image" "$output_image" 2>&1) || {
        echo "$converter_output" >&2
        echo "ERROR: failed to render $source_image" >&2
        exit 1
    }
    if [[ -n "$converter_output" ]]; then
        echo "$converter_output" >&2
        echo "ERROR: image conversion emitted diagnostic output" >&2
        exit 1
    fi
    if [[ ! -s "$output_image" ]]; then
        echo "ERROR: image conversion produced an empty file: $output_image" >&2
        exit 1
    fi

    if [[ "$image_name" == final_cpu_architecture ]]; then
        count_file="$report_directory/final_cpu_architecture_counts.txt"
        if [[ ! -s "$count_file" ]]; then
            echo "ERROR: missing CPU architecture count file: $count_file" >&2
            exit 1
        fi
        decode_control_count=
        register_bank_count=
        alu_datapath_count=
        biu_shared_count=
        while read -r architecture_group architecture_count; do
            case "$architecture_group" in
                decode_control) decode_control_count=$architecture_count ;;
                register_bank) register_bank_count=$architecture_count ;;
                alu_datapath) alu_datapath_count=$architecture_count ;;
                biu_shared) biu_shared_count=$architecture_count ;;
                *)
                    echo "ERROR: unknown CPU architecture group: $architecture_group" >&2
                    exit 1
                    ;;
            esac
        done < "$count_file"
        if [[ -z "$decode_control_count" || -z "$register_bank_count" || \
              -z "$alu_datapath_count" || -z "$biu_shared_count" ]]; then
            echo "ERROR: incomplete CPU architecture counts: $count_file" >&2
            exit 1
        fi
        if [[ "$asic_design" == core ]]; then
            architecture_title="z8086 logic-only die - signed-off final placement"
        else
            architecture_title="z8086 CPU island - signed-off final placement"
        fi
        annotated_image="$output_directory/.final_cpu_architecture.annotated.png"
        annotation_output=$(magick \
            -size 1600x100 xc:black \
            -font Helvetica -fill white -pointsize 26 \
            -annotate +30+32 "$architecture_title" \
            -fill '#00ff00' -draw 'rectangle 30,55 52,77' \
            -fill white -pointsize 21 -annotate +62+75 "Decode / control ($decode_control_count)" \
            -fill '#ffff00' -draw 'rectangle 405,55 427,77' \
            -fill white -annotate +437+75 "Register bank ($register_bank_count)" \
            -fill '#ff00ff' -draw 'rectangle 765,55 787,77' \
            -fill white -annotate +797+75 "ALU / datapath ($alu_datapath_count)" \
            -fill '#ff2020' -draw 'rectangle 1095,55 1117,77' \
            -fill white -annotate +1127+75 "BIU / shared ($biu_shared_count)" \
            "$output_image" -append "$annotated_image" 2>&1) || {
            echo "$annotation_output" >&2
            echo "ERROR: failed to annotate $output_image" >&2
            exit 1
        }
        if [[ -n "$annotation_output" ]]; then
            echo "$annotation_output" >&2
            echo "ERROR: CPU architecture annotation emitted diagnostic output" >&2
            exit 1
        fi
        mv "$annotated_image" "$output_image"
    fi
done

echo "PASS: rendered ${#images[@]} warning-free Nangate45 PNGs for $design_name"
echo "output: $output_directory"
