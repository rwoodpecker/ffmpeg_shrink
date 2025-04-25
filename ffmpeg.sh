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

# ✅ Validate input path (either file or directory)
if [[ $# -ne 1 ]]; then
    echo "❌ Usage: $0 [--crf <value>] [--speed <preset>] /path/to/input.[mov|mp4|mkv] or /path/to/directory"
    echo "    Example (file): $0 --crf 18 --speed slow /path/to/video.mp4"
    echo "    Example (directory): $0 /path/to/directory"
    exit 1
fi
input_path="$1"

# ✅ Check that required tools are installed
command -v ffmpeg >/dev/null 2>&1 || { echo "❌ ffmpeg not found."; exit 1; }
command -v exiftool >/dev/null 2>&1 || { echo "❌ exiftool not found."; exit 1; }
command -v SetFile >/dev/null 2>&1 || echo "⚠️ SetFile not found (macOS timestamp sync may fail)."

# ✅ Function to process individual files
process_file() {
    input_file="$1"
    filename=$(basename -- "$input_file")
    name="${filename%.*}"
    ext="${filename##*.}"
    ext_lower=$(echo "$ext" | tr '[:upper:]' '[:lower:]')

    # ✅ Supported formats (no .avi)
    valid_exts=("mov" "mp4" "mkv")
    is_valid=false
    for valid in "${valid_exts[@]}"; do
        if [[ "$ext_lower" == "$valid" ]]; then
            is_valid=true
            break
        fi
    done

    if [[ "$is_valid" != true ]]; then
        echo "❌ Skipping unsupported file: $filename"
        return
    fi

    # ✅ Set output paths with _compressed
    input_dir=$(dirname "$input_file")
    output_mp4="${input_dir}/${name}_compressed_ffmpeg-raw.mp4"
    final_mp4="${input_dir}/${name}_compressed.mp4"

    # ⚠️ Check for existing files
    if [[ -f "$output_mp4" || -f "$final_mp4" ]]; then
        echo "⚠️ Warning: Output files already exist for '$filename':"
        [[ -f "$output_mp4" ]] && echo " - $output_mp4"
        [[ -f "$final_mp4" ]] && echo " - $final_mp4"
        echo -n "❓ Overwrite? [y/N]: "
        read -r confirm
        if [[ "${confirm,,}" != "y" ]]; then
            echo "🛑 Skipping file."
            return
        fi
    fi

    # 🎬 FFmpeg Conversion
    echo "🚀 Converting '$input_file' to '$output_mp4'..."
    echo "   ➤ CRF: $crf"
    echo "   ➤ Speed: $speed"
    if ffmpeg -hide_banner -loglevel info -stats -i "$input_file" \
        -c:v libx265 -preset "$speed" -crf "$crf" -tag:v hvc1 \
        -movflags use_metadata_tags "$output_mp4"; then
        echo "✅ FFmpeg conversion complete: $output_mp4"
    else
        echo "❌ FFmpeg conversion failed for '$input_file'."
        return
    fi

    # 📋 Metadata Copying
    echo "🔄 Copying metadata to: $final_mp4"
    cp "$output_mp4" "$final_mp4"
    if ! exiftool -v -m -overwrite_original \
        -api QuickTimeUTC=1 -api LargeFileSupport=1 \
        -tagsFromFile "$input_file" -All:All \
        '-FileCreateDate<QuickTime:CreateDate' \
        '-FileModifyDate<QuickTime:CreateDate' "$final_mp4"; then
        echo "❌ Metadata copy failed."
        return
    fi

    # 🧹 Fixing Metadata Keys
    echo "🧹 Fixing Keys metadata..."
    if ! exiftool -m -overwrite_original -api LargeFileSupport=1 \
        -Keys:All= -tagsFromFile @ -Keys:All "$final_mp4"; then
        echo "❌ Failed to fix Keys metadata."
        return
    fi

    # 🕒 Syncing Timestamps (macOS only)
    echo "🕒 Syncing timestamps..."
    CREATION_TIME=$(GetFileInfo -d "$input_file")
    MODIFICATION_TIME=$(GetFileInfo -m "$input_file")
    SetFile -d "$CREATION_TIME" "$output_mp4"
    SetFile -d "$CREATION_TIME" "$final_mp4"
    SetFile -m "$MODIFICATION_TIME" "$output_mp4"
    SetFile -m "$MODIFICATION_TIME" "$final_mp4"

    echo "✅ Timestamps synced to match original file"

    # ✅ All done
    echo "🎉 Done: $final_mp4"
    echo
}

# 🧩 Handle input paths: file or directory
if [[ -d "$input_path" ]]; then
    echo "📂 Processing directory: $input_path"
    shopt -s nullglob
    for file in "$input_path"/*.{mov,mp4,mkv,MOV,MP4,MKV}; do
        process_file "$file"
    done
else
    process_file "$input_path"
fi
