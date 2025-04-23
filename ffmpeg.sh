#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# ✅ Default values
crf=24
speed="veryslow"

# 🧩 Parse optional flags
POSITIONAL=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --crf)
            crf="$2"
            shift 2
            ;;
        --speed)
            speed="$2"
            shift 2
            ;;
        -*)
            echo "❌ Unknown option: $1"
            exit 1
            ;;
        *)
            POSITIONAL+=("$1")
            shift
            ;;
    esac
done

# 🧠 Restore positional parameters (just the input file)
set -- "${POSITIONAL[@]}"
if [[ $# -ne 1 ]]; then
    echo "❌ Usage: $0 [--crf <value>] [--speed <preset>] /path/to/input.MOV"
    echo "    Default: --crf 24 --speed veryslow"
    exit 1
fi

input_file="$1"

# ✅ Validate input file exists
if [[ ! -f "$input_file" ]]; then
    echo "❌ Error: File '$input_file' not found."
    exit 1
fi

# ✅ Extract base filename and extension
filename=$(basename -- "$input_file")
name="${filename%.*}"
ext="${filename##*.}"

# ✅ Confirm it's a .MOV file (case-insensitive)
if [[ "$(echo "$ext" | tr '[:upper:]' '[:lower:]')" != "mov" ]]; then
    echo "❌ Error: Input file must have a .MOV extension."
    exit 1
fi

# ✅ Set output paths
input_dir=$(dirname "$input_file")
output_mp4="${input_dir}/${name}_ffmpeg-raw.mp4"
final_mp4="${input_dir}/${name}.mp4"

# ⚠️ Check for existing files
if [[ -f "$output_mp4" || -f "$final_mp4" ]]; then
    echo "⚠️ Warning: One or both output files already exist:"
    [[ -f "$output_mp4" ]] && echo " - $output_mp4"
    [[ -f "$final_mp4" ]] && echo " - $final_mp4"
    echo -n "❓ Do you want to overwrite them? [y/N]: "
    read -r confirm
    if [[ "${confirm,,}" != "y" ]]; then
        echo "🛑 Aborted by user."
        exit 1
    fi
fi

# 🎬 FFmpeg Conversion
echo "🚀 Converting '$input_file' to '$output_mp4' using ffmpeg..."
echo "   ➤ CRF: $crf"
echo "   ➤ Speed (ffmpeg preset): $speed"
if ffmpeg -hide_banner -loglevel info -stats -i "$input_file" \
    -c:v libx265 -preset "$speed" -crf "$crf" -tag:v hvc1 \
    -movflags use_metadata_tags "$output_mp4"; then
    echo "✅ FFmpeg conversion complete: $output_mp4"
else
    echo "❌ FFmpeg conversion failed."
    exit 1
fi

# 📋 Metadata Copying
echo "🔄 Copying metadata from '$input_file' to '$final_mp4' using exiftool..."
cp "$output_mp4" "$final_mp4"
if exiftool -v -m -overwrite_original \
    -api QuickTimeUTC=1 -api LargeFileSupport=1 \
    -tagsFromFile "$input_file" -All:All \
    '-FileCreateDate<QuickTime:CreateDate' \
    '-FileModifyDate<QuickTime:CreateDate' "$final_mp4"; then
    echo "✅ Metadata copied to: $final_mp4"
else
    echo "❌ Metadata copying failed."
    exit 1
fi

# 🧹 Final Metadata Fix: Clean and rebuild Keys tags
echo "🧹 Fixing Keys metadata in '$final_mp4'..."
if exiftool -m -overwrite_original -api LargeFileSupport=1 \
    -Keys:All= -tagsFromFile @ -Keys:All "$final_mp4"; then
    echo "✅ Keys metadata cleaned and rebuilt in: $final_mp4"
else
    echo "❌ Failed to fix Keys metadata."
    exit 1
fi

# 🕒 Sync timestamps using SetFile (macOS only)
echo "🕒 Syncing timestamps from original .MOV to output files..."
CREATION_TIME=$(GetFileInfo -d "$input_file")
MODIFICATION_TIME=$(GetFileInfo -m "$input_file")

SetFile -d "$CREATION_TIME" "$output_mp4"
SetFile -d "$CREATION_TIME" "$final_mp4"
SetFile -m "$MODIFICATION_TIME" "$output_mp4"
SetFile -m "$MODIFICATION_TIME" "$final_mp4"

echo "✅ Timestamps synced to match original file"

# ✅ All done
echo "🎉 All done — files created:"
echo "  - Intermediate video (ffmpeg output, no metadata): $output_mp4"
echo "  - Final .mp4 with metadata and correct timestamps: $final_mp4"
