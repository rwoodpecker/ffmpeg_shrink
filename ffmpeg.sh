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

# ✅ Validate input path
if [[ $# -ne 1 ]]; then
    echo "❌ Usage: $0 [--crf <value>] [--speed <preset>] /path/to/input.[mov|mp4|mkv] or /path/to/directory"
    exit 1
fi
input_path="$1"

# ✅ Check dependencies
command -v ffmpeg >/dev/null 2>&1 || { echo "❌ ffmpeg not found."; exit 1; }
command -v exiftool >/dev/null 2>&1 || { echo "❌ exiftool not found."; exit 1; }
command -v SetFile >/dev/null 2>&1 || echo "⚠️ SetFile not found (macOS timestamp sync may fail)."

# ✅ Function to convert bytes to human-readable size
human_readable() {
    b=$1
    if [[ $b -gt 1073741824 ]]; then
        printf "%.2f GB" "$(echo "$b / 1073741824" | bc -l)"
    elif [[ $b -gt 1048576 ]]; then
        printf "%.2f MB" "$(echo "$b / 1048576" | bc -l)"
    elif [[ $b -gt 1024 ]]; then
        printf "%.2f KB" "$(echo "$b / 1024" | bc -l)"
    else
        echo "$b B"
    fi
}

# ✅ Process individual files
process_file() {
    input_file="$1"
    filename=$(basename -- "$input_file")
    name="${filename%.*}"
    ext="${filename##*.}"
    ext_lower=$(echo "$ext" | tr '[:upper:]' '[:lower:]')

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

    input_dir=$(dirname "$input_file")
    raw_dir="${input_dir}/ffmpeg_raw"
    mkdir -p "$raw_dir"

    output_mp4="${raw_dir}/${name}_compressed_ffmpeg-raw.mp4"
    final_mp4="${input_dir}/${name}_compressed.mp4"

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

    # 🧠 Input metadata
    duration=$(ffprobe -v error -show_entries format=duration \
        -of default=noprint_wrappers=1:nokey=1 "$input_file" | awk '{printf "%.2f", $1}')
    resolution=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height \
        -of csv=p=0:s=x "$input_file")
    codec_info="libx265 (HEVC)"

    echo "🚀 Converting '$input_file' to '$output_mp4'..."
    echo "   ➤ CRF: $crf"
    echo "   ➤ Speed: $speed"
    echo "   🎞 Resolution: $resolution"
    echo "   🕒 Duration: ${duration}s"
    echo "   🔧 Codec: $codec_info"

    start_time=$(date +%s)
    if ffmpeg -hide_banner -loglevel info -stats -i "$input_file" \
        -c:v libx265 -preset "$speed" -crf "$crf" -tag:v hvc1 \
        -movflags use_metadata_tags "$output_mp4"; then
        end_time=$(date +%s)
        elapsed=$((end_time - start_time))
        echo "✅ FFmpeg conversion complete: $output_mp4"
        echo "⏱ Time taken: ${elapsed}s"
    else
        echo "❌ FFmpeg conversion failed for '$input_file'."
        return
    fi

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

    echo "🧹 Fixing Keys metadata..."
    if ! exiftool -m -overwrite_original -api LargeFileSupport=1 \
        -Keys:All= -tagsFromFile @ -Keys:All "$final_mp4"; then
        echo "❌ Failed to fix Keys metadata."
        return
    fi

    echo "🕒 Syncing timestamps..."
    CREATION_TIME=$(GetFileInfo -d "$input_file")
    MODIFICATION_TIME=$(GetFileInfo -m "$input_file")
    SetFile -d "$CREATION_TIME" "$output_mp4"
    SetFile -d "$CREATION_TIME" "$final_mp4"
    SetFile -m "$MODIFICATION_TIME" "$output_mp4"
    SetFile -m "$MODIFICATION_TIME" "$final_mp4"
    echo "✅ Timestamps synced."

    # 📊 Space savings
    echo "📊 Calculating space saved..."
    orig_size=$(stat -f%z "$input_file" 2>/dev/null || stat -c%s "$input_file")
    final_size=$(stat -f%z "$final_mp4" 2>/dev/null || stat -c%s "$final_mp4")
    saved_bytes=$((orig_size - final_size))

    echo "📦 Original size: $(human_readable "$orig_size")"
    echo "🧱 Compressed size: $(human_readable "$final_size")"
    if [[ $saved_bytes -gt 0 ]]; then
        echo "✅ Saved: $(human_readable "$saved_bytes")"
    else
        echo "⚠️ No space saved (or file grew slightly)."
    fi

    echo "🎉 Done: $final_mp4"
    echo
}

# 🧩 Handle input path
if [[ -d "$input_path" ]]; then
    echo "📂 Processing directory: $input_path"
    shopt -s nullglob
    for file in "$input_path"/*.{mov,mp4,mkv,MOV,MP4,MKV}; do
        process_file "$file"
    done
else
    process_file "$input_path"
fi
