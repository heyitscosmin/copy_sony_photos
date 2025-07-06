#!/bin/bash

# Sony A6400 Advanced Photo Copy Script
# High-performance script with all optimizations for copying photos from Sony camera

# Version and metadata
SCRIPT_VERSION="2.0.1"
SCRIPT_NAME="Sony Photo Copy Advanced"

# Default configuration
CAMERA_MOUNT_PATH="/Volumes/SonyA6400/DCIM/100MSDCF"
PHOTOS_DEST="$HOME/Sony-photos"
LOG_FILE="$HOME/sony_photo_copy.log"
CONFIG_FILE="$HOME/.sony_camera_config"

# Advanced optimization settings
COPY_ONLY_NEW=true
USE_PARALLEL=true
PARALLEL_JOBS=4
USE_RSYNC=true
VERIFY_INTEGRITY=true
ORGANIZE_BY_DATE=false
DATE_FORMAT="readable"  # Options: "readable" (2023-12-25_Dec), "simple" (2023-12-25), "compact" (20231225)
DAYS_FILTER=0
MIN_FILE_SIZE=1024
MAX_FILE_SIZE=0
COPY_JPG=true
COPY_RAW=true
FLATTEN_STRUCTURE=false
BANDWIDTH_LIMIT=0
RETRY_COUNT=3
DRY_RUN=false
VERBOSE=false
QUICK_MODE=false
PROGRESS_BAR=true
CREATE_CHECKSUM=false

# Colors and formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'
BOLD='\033[1m'

# Global statistics
TOTAL_FILES=0
COPIED_FILES=0
SKIPPED_FILES=0
FAILED_FILES=0
JPG_COPIED=0
RAW_COPIED=0
BYTES_COPIED=0
START_TIME=$(date +%s)

# Logging functions
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

print_header() {
    echo -e "${BOLD}${CYAN}$SCRIPT_NAME v$SCRIPT_VERSION${NC}"
    echo -e "${CYAN}========================================${NC}"
}

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
    [ "$VERBOSE" = true ] && log_message "INFO: $1"
}

print_verbose() {
    [ "$VERBOSE" = true ] && echo -e "${BLUE}[VERBOSE]${NC} $1"
    [ "$VERBOSE" = true ] && log_message "VERBOSE: $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    log_message "WARNING: $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    log_message "ERROR: $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    log_message "SUCCESS: $1"
}

# Progress bar function
show_progress() {
    local current=$1
    local total=$2
    local prefix=$3
    local suffix=$4
    local bar_length=50
    
    if [ "$PROGRESS_BAR" = false ] || [ "$total" -eq 0 ]; then
        return
    fi
    
    local progress=$((current * 100 / total))
    local filled=$((current * bar_length / total))
    local empty=$((bar_length - filled))
    
    printf "\r${prefix} ["
    printf "%${filled}s" | tr ' ' '='
    printf "%${empty}s" | tr ' ' '-'
    printf "] %d%% (%d/%d) %s" "$progress" "$current" "$total" "$suffix"
}

# Configuration management
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        print_verbose "Loading configuration from $CONFIG_FILE"
        source "$CONFIG_FILE"
    fi
}

save_config() {
    print_verbose "Saving configuration to $CONFIG_FILE"
    cat > "$CONFIG_FILE" << EOF
# Sony Camera Photo Copy Configuration
# Generated on $(date)

CAMERA_MOUNT_PATH="$CAMERA_MOUNT_PATH"
PHOTOS_DEST="$PHOTOS_DEST"
COPY_ONLY_NEW=$COPY_ONLY_NEW
USE_PARALLEL=$USE_PARALLEL
PARALLEL_JOBS=$PARALLEL_JOBS
USE_RSYNC=$USE_RSYNC
VERIFY_INTEGRITY=$VERIFY_INTEGRITY
ORGANIZE_BY_DATE=$ORGANIZE_BY_DATE
DATE_FORMAT="$DATE_FORMAT"
DAYS_FILTER=$DAYS_FILTER
MIN_FILE_SIZE=$MIN_FILE_SIZE
MAX_FILE_SIZE=$MAX_FILE_SIZE
COPY_JPG=$COPY_JPG
COPY_RAW=$COPY_RAW
FLATTEN_STRUCTURE=$FLATTEN_STRUCTURE
BANDWIDTH_LIMIT=$BANDWIDTH_LIMIT
RETRY_COUNT=$RETRY_COUNT
PROGRESS_BAR=$PROGRESS_BAR
CREATE_CHECKSUM=$CREATE_CHECKSUM
EOF
}

# Utility functions
check_dependencies() {
    local deps=("find" "rsync" "shasum" "stat")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            print_error "Required dependency '$dep' not found"
            exit 1
        fi
    done
}

get_file_size() {
    stat -f%z "$1" 2>/dev/null || echo 0
}

get_file_date() {
    stat -f%Sm -t%Y-%m-%d "$1" 2>/dev/null || echo "unknown"
}

get_exif_date() {
    if command -v exiftool &> /dev/null; then
        exiftool -d "%Y-%m-%d" -DateTimeOriginal -s -s -s "$1" 2>/dev/null || get_file_date "$1"
    else
        get_file_date "$1"
    fi
}

get_human_readable_date() {
    local file_path="$1"
    local raw_date
    
    if command -v exiftool &> /dev/null; then
        raw_date=$(exiftool -d "%Y-%m-%d" -DateTimeOriginal -s -s -s "$file_path" 2>/dev/null)
    fi
    
    if [ -z "$raw_date" ]; then
        raw_date=$(get_file_date "$file_path")
    fi
    
    if [ "$raw_date" = "unknown" ]; then
        echo "unknown"
        return
    fi
    
    # Convert YYYY-MM-DD to YYYY-MM-DD_MonthName format
    local year=$(echo "$raw_date" | cut -d'-' -f1)
    local month=$(echo "$raw_date" | cut -d'-' -f2)
    local day=$(echo "$raw_date" | cut -d'-' -f3)
    
    # Get month name
    local month_name
    case "$month" in
        01) month_name="Jan" ;;
        02) month_name="Feb" ;;
        03) month_name="Mar" ;;
        04) month_name="Apr" ;;
        05) month_name="May" ;;
        06) month_name="Jun" ;;
        07) month_name="Jul" ;;
        08) month_name="Aug" ;;
        09) month_name="Sep" ;;
        10) month_name="Oct" ;;
        11) month_name="Nov" ;;
        12) month_name="Dec" ;;
        *) month_name="UnknownMonth" ;;
    esac
    
    echo "${year}-${month}-${day}_${month_name}"
}

format_bytes() {
    local bytes=$1
    if [ "$bytes" -lt 1024 ]; then
        echo "${bytes}B"
    elif [ "$bytes" -lt 1048576 ]; then
        echo "$((bytes / 1024))KB"
    elif [ "$bytes" -lt 1073741824 ]; then
        echo "$((bytes / 1048576))MB"
    else
        echo "$((bytes / 1073741824))GB"
    fi
}

# File filtering and validation
should_copy_file() {
    local file_path="$1"
    local filename=$(basename "$file_path")
    local extension="${filename##*.}"
    local extension_lower=$(echo "$extension" | tr '[:upper:]' '[:lower:]')
    local file_size=$(get_file_size "$file_path")
    
    # Skip hidden files and system files
    if [[ "$filename" =~ ^\. ]]; then
        print_verbose "Skipping hidden/system file: $filename"
        return 1
    fi
    
    # Skip common metadata files
    if [[ "$filename" =~ ^(Thumbs\.db|Desktop\.ini|\.DS_Store)$ ]]; then
        print_verbose "Skipping metadata file: $filename"
        return 1
    fi
    
    # Check file type
    if [[ "$extension_lower" == "arw" ]] && [ "$COPY_RAW" = false ]; then
        print_verbose "Skipping RAW file (disabled): $filename"
        return 1
    fi
    
    if [[ "$extension_lower" =~ ^(jpg|jpeg)$ ]] && [ "$COPY_JPG" = false ]; then
        print_verbose "Skipping JPG file (disabled): $filename"
        return 1
    fi
    
    # Check file size
    if [ "$file_size" -lt "$MIN_FILE_SIZE" ]; then
        print_verbose "Skipping small file ($file_size bytes): $filename"
        return 1
    fi
    
    if [ "$MAX_FILE_SIZE" -gt 0 ] && [ "$file_size" -gt "$MAX_FILE_SIZE" ]; then
        print_verbose "Skipping large file ($file_size bytes): $filename"
        return 1
    fi
    
    # Check date filter
    if [ "$DAYS_FILTER" -gt 0 ]; then
        local file_date=$(get_file_date "$file_path")
        local cutoff_date=$(date -v-${DAYS_FILTER}d +%Y-%m-%d)
        print_verbose "Date check: file=$file_date, cutoff=$cutoff_date, days_filter=$DAYS_FILTER"
        if [ "$file_date" != "unknown" ]; then
            # Convert dates to seconds since epoch for proper comparison
            local file_seconds=$(date -j -f "%Y-%m-%d" "$file_date" "+%s" 2>/dev/null || echo "0")
            local cutoff_seconds=$(date -j -f "%Y-%m-%d" "$cutoff_date" "+%s" 2>/dev/null || echo "0")
            if [ "$file_seconds" -lt "$cutoff_seconds" ] && [ "$file_seconds" -gt 0 ] && [ "$cutoff_seconds" -gt 0 ]; then
                print_verbose "Skipping old file ($file_date < $cutoff_date): $filename"
                return 1
            fi
        fi
    fi
    
    return 0
}

# Enhanced duplicate detection with size and hash comparison
file_already_exists() {
    local filename="$1"
    local extension_lower="$2"
    local source_size="$3"
    local source_path="$4"
    
    # Quick name-based check first
    local search_pattern
    if [[ "$extension_lower" == "arw" ]]; then
        search_pattern="ARW/$filename"
    else
        search_pattern="JPG/$filename"
    fi
    
    local existing_files
    existing_files=$(find "$PHOTOS_DEST" -path "*/$search_pattern" -type f 2>/dev/null)
    
    if [ -z "$existing_files" ]; then
        return 1  # Not found
    fi
    
    # If found, check size for quick verification
    while IFS= read -r existing_file; do
        if [ -f "$existing_file" ]; then
            local existing_size=$(get_file_size "$existing_file")
            if [ "$existing_size" -eq "$source_size" ]; then
                print_verbose "Duplicate found (same size): $filename"
                return 0  # Duplicate found
            fi
        fi
    done <<< "$existing_files"
    
    return 1  # No exact duplicate found
}

# Parallel file copying with rsync or cp
copy_files_parallel() {
    local file_list="$1"
    local jpg_dest="$2"
    local arw_dest="$3"
    
    if [ ! -s "$file_list" ]; then
        return 0
    fi
    
    if [ "$USE_RSYNC" = true ]; then
        if [ "$USE_PARALLEL" = true ]; then
            print_status "Using parallel rsync for optimized copying (${PARALLEL_JOBS} jobs)..."
            
            # Build rsync options
            local rsync_opts=("-avh")
            
            if [ "$BANDWIDTH_LIMIT" -gt 0 ]; then
                rsync_opts+=("--bwlimit=$BANDWIDTH_LIMIT")
            fi
            
            if [ "$VERBOSE" = true ]; then
                rsync_opts+=("-v")
            fi
            
            # Use parallel processing with background jobs (avoiding xargs completely)
            local active_jobs=0
            local job_pids=()
            local temp_stats=$(mktemp)
            
            # Initialize stats file
            echo "COPIED=0" > "$temp_stats"
            echo "FAILED=0" >> "$temp_stats"
            echo "JPG=0" >> "$temp_stats"
            echo "RAW=0" >> "$temp_stats"
            echo "BYTES=0" >> "$temp_stats"
            
            # Function to copy a single file in background
            copy_file_bg() {
                local source_path="$1"
                local dest_path="$2"
                local stats_file="$3"
                local filename=$(basename "$source_path")
                
                if [ "$DRY_RUN" = true ]; then
                    echo "DRY RUN: Would copy $filename"
                    # Update stats atomically using temp file and rename (atomic operation)
                    local temp_update=$(mktemp)
                    (
                        if [ -f "$stats_file" ]; then
                            source "$stats_file"
                        else
                            COPIED=0; FAILED=0; JPG=0; RAW=0; BYTES=0
                        fi
                        echo "COPIED=$((COPIED + 1))" > "$temp_update"
                        echo "FAILED=$FAILED" >> "$temp_update"
                        echo "JPG=$JPG" >> "$temp_update"
                        echo "RAW=$RAW" >> "$temp_update"
                        echo "BYTES=$BYTES" >> "$temp_update"
                        mv "$temp_update" "$stats_file"
                    )
                else
                    # Build rsync command with proper options
                    local rsync_cmd=("rsync" "-avh")
                    if [ "$BANDWIDTH_LIMIT" -gt 0 ]; then
                        rsync_cmd+=("--bwlimit=$BANDWIDTH_LIMIT")
                    fi
                    
                    if "${rsync_cmd[@]}" "$source_path" "$dest_path/" 2>/dev/null; then
                        echo "Copied: $filename"
                        
                        # Update stats atomically using temp file and rename (atomic operation)
                        local temp_update=$(mktemp)
                        (
                            if [ -f "$stats_file" ]; then
                                source "$stats_file"
                            else
                                COPIED=0; FAILED=0; JPG=0; RAW=0; BYTES=0
                            fi
                            local file_size=$(stat -f%z "$dest_path/$(basename "$source_path")" 2>/dev/null || echo 0)
                            local new_copied=$((COPIED + 1))
                            local new_bytes=$((BYTES + file_size))
                            local new_jpg=$JPG
                            local new_raw=$RAW
                            
                            if [[ "$filename" =~ \.(arw|ARW)$ ]]; then
                                new_raw=$((RAW + 1))
                            else
                                new_jpg=$((JPG + 1))
                            fi
                            
                            echo "COPIED=$new_copied" > "$temp_update"
                            echo "FAILED=$FAILED" >> "$temp_update"
                            echo "JPG=$new_jpg" >> "$temp_update"
                            echo "RAW=$new_raw" >> "$temp_update"
                            echo "BYTES=$new_bytes" >> "$temp_update"
                            mv "$temp_update" "$stats_file"
                        )
                    else
                        echo "Failed: $filename"
                        # Update failed count atomically using temp file and rename
                        local temp_update=$(mktemp)
                        (
                            if [ -f "$stats_file" ]; then
                                source "$stats_file"
                            else
                                COPIED=0; FAILED=0; JPG=0; RAW=0; BYTES=0
                            fi
                            echo "COPIED=$COPIED" > "$temp_update"
                            echo "FAILED=$((FAILED + 1))" >> "$temp_update"
                            echo "JPG=$JPG" >> "$temp_update"
                            echo "RAW=$RAW" >> "$temp_update"
                            echo "BYTES=$BYTES" >> "$temp_update"
                            mv "$temp_update" "$stats_file"
                        )
                    fi
                fi
            }
            
            # Process each file
            while IFS= read -r file_info; do
                local source_path=$(echo "$file_info" | cut -d'|' -f1)
                local dest_path=$(echo "$file_info" | cut -d'|' -f2)
                
                # Wait if we have too many active jobs
                while [ "$active_jobs" -ge "$PARALLEL_JOBS" ]; do
                    # Check for completed jobs
                    local new_pids=()
                    for pid in "${job_pids[@]}"; do
                        if kill -0 "$pid" 2>/dev/null; then
                            new_pids+=("$pid")
                        else
                            ((active_jobs--))
                        fi
                    done
                    job_pids=("${new_pids[@]}")
                    
                    # Brief sleep to avoid busy waiting
                    if [ "$active_jobs" -ge "$PARALLEL_JOBS" ]; then
                        sleep 0.1
                    fi
                done
                
                # Start new background job
                copy_file_bg "$source_path" "$dest_path" "$temp_stats" &
                local new_pid=$!
                job_pids+=("$new_pid")
                ((active_jobs++))
                
            done < "$file_list"
            
            # Wait for all remaining jobs to complete
            for pid in "${job_pids[@]}"; do
                wait "$pid" 2>/dev/null
            done
            
            # Update global statistics from temp file
            if [ -f "$temp_stats" ]; then
                source "$temp_stats"
                COPIED_FILES=$COPIED
                FAILED_FILES=$FAILED
                JPG_COPIED=$JPG
                RAW_COPIED=$RAW
                BYTES_COPIED=$BYTES
            fi
            
            # Cleanup
            rm -f "$temp_stats"
        else
            print_status "Using sequential rsync for copying..."
            
            # Build rsync options
            local rsync_opts=("-avh" "--progress")
            
            if [ "$BANDWIDTH_LIMIT" -gt 0 ]; then
                rsync_opts+=("--bwlimit=$BANDWIDTH_LIMIT")
            fi
            
            if [ "$VERBOSE" = true ]; then
                rsync_opts+=("-v")
            fi
            
            # Copy files with rsync sequentially
            while IFS= read -r file_info; do
                local source_path=$(echo "$file_info" | cut -d'|' -f1)
                local dest_path=$(echo "$file_info" | cut -d'|' -f2)
                local filename=$(basename "$source_path")
                
                if [ "$DRY_RUN" = true ]; then
                    print_status "DRY RUN: Would copy $filename"
                    ((COPIED_FILES++))
                else
                    print_verbose "Copying with rsync: $filename"
                    if rsync "${rsync_opts[@]}" "$source_path" "$dest_path/"; then
                        ((COPIED_FILES++))
                        local file_size=$(get_file_size "$dest_path/$(basename "$source_path")")
                        BYTES_COPIED=$((BYTES_COPIED + file_size))
                        
                        if [[ "$filename" =~ \.(arw|ARW)$ ]]; then
                            ((RAW_COPIED++))
                        else
                            ((JPG_COPIED++))
                        fi
                        
                        # Verify integrity if enabled
                        if [ "$VERIFY_INTEGRITY" = true ]; then
                            verify_file_integrity "$source_path" "$dest_path/$(basename "$source_path")"
                        fi
                    else
                        print_error "Failed to copy: $filename"
                        ((FAILED_FILES++))
                    fi
                fi
            done < "$file_list"
        fi
    else
        # Use parallel cp
        if [ "$USE_PARALLEL" = true ]; then
            print_status "Using parallel cp for copying (${PARALLEL_JOBS} jobs)..."
            
            # Use parallel processing with background jobs (avoiding xargs completely)
            local active_jobs=0
            local job_pids=()
            local temp_stats=$(mktemp)
            
            # Initialize stats file
            echo "COPIED=0" > "$temp_stats"
            echo "FAILED=0" >> "$temp_stats"
            echo "JPG=0" >> "$temp_stats"
            echo "RAW=0" >> "$temp_stats"
            echo "BYTES=0" >> "$temp_stats"
            
            # Function to copy a single file in background
            copy_file_bg() {
                local source_path="$1"
                local dest_path="$2"
                local stats_file="$3"
                local filename=$(basename "$source_path")
                
                if [ "$DRY_RUN" = true ]; then
                    echo "DRY RUN: Would copy $filename"
                    # Update stats atomically using temp file and rename (atomic operation)
                    local temp_update=$(mktemp)
                    (
                        if [ -f "$stats_file" ]; then
                            source "$stats_file"
                        else
                            COPIED=0; FAILED=0; JPG=0; RAW=0; BYTES=0
                        fi
                        echo "COPIED=$((COPIED + 1))" > "$temp_update"
                        echo "FAILED=$FAILED" >> "$temp_update"
                        echo "JPG=$JPG" >> "$temp_update"
                        echo "RAW=$RAW" >> "$temp_update"
                        echo "BYTES=$BYTES" >> "$temp_update"
                        mv "$temp_update" "$stats_file"
                    )
                else
                    if cp "$source_path" "$dest_path/" 2>/dev/null; then
                        echo "Copied: $filename"
                        
                        # Update stats atomically using temp file and rename (atomic operation)
                        local temp_update=$(mktemp)
                        (
                            if [ -f "$stats_file" ]; then
                                source "$stats_file"
                            else
                                COPIED=0; FAILED=0; JPG=0; RAW=0; BYTES=0
                            fi
                            local file_size=$(stat -f%z "$dest_path/$(basename "$source_path")" 2>/dev/null || echo 0)
                            local new_copied=$((COPIED + 1))
                            local new_bytes=$((BYTES + file_size))
                            local new_jpg=$JPG
                            local new_raw=$RAW
                            
                            if [[ "$filename" =~ \.(arw|ARW)$ ]]; then
                                new_raw=$((RAW + 1))
                            else
                                new_jpg=$((JPG + 1))
                            fi
                            
                            echo "COPIED=$new_copied" > "$temp_update"
                            echo "FAILED=$FAILED" >> "$temp_update"
                            echo "JPG=$new_jpg" >> "$temp_update"
                            echo "RAW=$new_raw" >> "$temp_update"
                            echo "BYTES=$new_bytes" >> "$temp_update"
                            mv "$temp_update" "$stats_file"
                        )
                    else
                        echo "Failed: $filename"
                        # Update failed count atomically using temp file and rename
                        local temp_update=$(mktemp)
                        (
                            if [ -f "$stats_file" ]; then
                                source "$stats_file"
                            else
                                COPIED=0; FAILED=0; JPG=0; RAW=0; BYTES=0
                            fi
                            echo "COPIED=$COPIED" > "$temp_update"
                            echo "FAILED=$((FAILED + 1))" >> "$temp_update"
                            echo "JPG=$JPG" >> "$temp_update"
                            echo "RAW=$RAW" >> "$temp_update"
                            echo "BYTES=$BYTES" >> "$temp_update"
                            mv "$temp_update" "$stats_file"
                        )
                    fi
                fi
            }
            
            # Process each file
            while IFS= read -r file_info; do
                local source_path=$(echo "$file_info" | cut -d'|' -f1)
                local dest_path=$(echo "$file_info" | cut -d'|' -f2)
                
                # Wait if we have too many active jobs
                while [ "$active_jobs" -ge "$PARALLEL_JOBS" ]; do
                    # Check for completed jobs
                    local new_pids=()
                    for pid in "${job_pids[@]}"; do
                        if kill -0 "$pid" 2>/dev/null; then
                            new_pids+=("$pid")
                        else
                            ((active_jobs--))
                        fi
                    done
                    job_pids=("${new_pids[@]}")
                    
                    # Brief sleep to avoid busy waiting
                    if [ "$active_jobs" -ge "$PARALLEL_JOBS" ]; then
                        sleep 0.1
                    fi
                done
                
                # Start new background job
                copy_file_bg "$source_path" "$dest_path" "$temp_stats" &
                local new_pid=$!
                job_pids+=("$new_pid")
                ((active_jobs++))
                
            done < "$file_list"
            
            # Wait for all remaining jobs to complete
            for pid in "${job_pids[@]}"; do
                wait "$pid" 2>/dev/null
            done
            
            # Update global statistics from temp file
            if [ -f "$temp_stats" ]; then
                source "$temp_stats"
                COPIED_FILES=$COPIED
                FAILED_FILES=$FAILED
                JPG_COPIED=$JPG
                RAW_COPIED=$RAW
                BYTES_COPIED=$BYTES
            fi
            
            # Cleanup
            rm -f "$temp_stats"
        else
            print_status "Using sequential cp for copying..."
            
            # Sequential copying
            while IFS= read -r file_info; do
                local source_path=$(echo "$file_info" | cut -d'|' -f1)
                local dest_path=$(echo "$file_info" | cut -d'|' -f2)
                local filename=$(basename "$source_path")
                
                if [ "$DRY_RUN" = true ]; then
                    print_status "DRY RUN: Would copy $filename"
                else
                    if cp "$source_path" "$dest_path/"; then
                        print_verbose "Copied: $filename"
                        ((COPIED_FILES++))
                    else
                        print_error "Failed to copy: $filename"
                        ((FAILED_FILES++))
                    fi
                fi
            done < "$file_list"
        fi
    fi
}

# File integrity verification
verify_file_integrity() {
    local source_file="$1"
    local dest_file="$2"
    
    local source_size=$(get_file_size "$source_file")
    local dest_size=$(get_file_size "$dest_file")
    
    if [ "$source_size" -ne "$dest_size" ]; then
        print_error "Size mismatch for $(basename "$dest_file")"
        return 1
    fi
    
    if [ "$CREATE_CHECKSUM" = true ]; then
        local source_hash=$(shasum -a 256 "$source_file" | cut -d' ' -f1)
        local dest_hash=$(shasum -a 256 "$dest_file" | cut -d' ' -f1)
        
        if [ "$source_hash" != "$dest_hash" ]; then
            print_error "Checksum mismatch for $(basename "$dest_file")"
            return 1
        fi
        
        print_verbose "Checksum verified: $(basename "$dest_file")"
    fi
    
    return 0
}

# Main processing function
main() {
    local temp_file_list=$(mktemp)
    trap "rm -f $temp_file_list" EXIT
    
    print_header
    
    # Check dependencies
    check_dependencies
    
    # Validate camera mount
    if [ ! -d "$CAMERA_MOUNT_PATH" ]; then
        print_error "Camera mount path not found: $CAMERA_MOUNT_PATH"
        print_status "Searching for alternative Sony camera mounts..."
        
        local found_cameras=()
        for path in /Volumes/Sony* /Volumes/DCIM* /Volumes/*A6400* /Volumes/*; do
            if [ -d "$path" ] && [ "$path" != "/Volumes" ]; then
                # Check if it looks like a camera (has DCIM folder)
                if [ -d "$path/DCIM" ]; then
                    found_cameras+=("$path")
                    print_status "Found potential camera mount: $path (has DCIM folder)"
                elif [[ "$path" =~ Sony|DCIM|A6400 ]]; then
                    found_cameras+=("$path")
                    print_status "Found potential camera mount: $path"
                fi
            fi
        done
        
        if [ ${#found_cameras[@]} -eq 0 ]; then
            print_error "No camera mounts detected. Please ensure your Sony camera is connected and mounted."
            print_status "Tip: Check if your camera appears in Finder under 'Locations'"
        else
            print_status "To use an alternative path, run:"
            for camera in "${found_cameras[@]}"; do
                if [ -d "$camera/DCIM" ]; then
                    for dcim_folder in "$camera/DCIM"/*; do
                        if [ -d "$dcim_folder" ]; then
                            print_status "  $0 '$dcim_folder'"
                            break
                        fi
                    done
                else
                    print_status "  $0 '$camera'"
                fi
            done
        fi
        exit 1
    fi
    
    # Create destination directories
    mkdir -p "$PHOTOS_DEST"
    
    # Use consistent folder structure (no timestamped imports)
    local jpg_folder="$PHOTOS_DEST/JPG"
    local arw_folder="$PHOTOS_DEST/ARW"
    
    if [ "$DRY_RUN" = false ]; then
        mkdir -p "$jpg_folder" "$arw_folder"
    fi
    
    print_status "Starting photo analysis..."
    
    # Find all photo files
    local photo_extensions=("jpg" "jpeg" "JPG" "JPEG" "arw" "ARW")
    local find_pattern=""
    for ext in "${photo_extensions[@]}"; do
        if [ -n "$find_pattern" ]; then
            find_pattern="$find_pattern -o"
        fi
        find_pattern="$find_pattern -iname *.${ext}"
    done
    
    # Count total files first for accurate progress
    print_status "Counting files..."
    local total_files_found=$(find "$CAMERA_MOUNT_PATH" -type f \( $find_pattern \) | wc -l | tr -d ' ')
    print_verbose "Found $total_files_found potential photo files"
    
    # Build file list with filtering
    local processed_count=0
    while IFS= read -r -d '' file_path; do
        ((processed_count++))
        
        if [ "$total_files_found" -gt 0 ] && [ "$((processed_count % 10))" -eq 0 ]; then
            show_progress "$processed_count" "$total_files_found" "Analyzing" "files..."
        fi
        
        if should_copy_file "$file_path"; then
            local filename=$(basename "$file_path")
            local extension="${filename##*.}"
            local extension_lower=$(echo "$extension" | tr '[:upper:]' '[:lower:]')
            local file_size=$(get_file_size "$file_path")
            
            ((TOTAL_FILES++))
            
            # Check for duplicates
            if [ "$COPY_ONLY_NEW" = true ] && file_already_exists "$filename" "$extension_lower" "$file_size" "$file_path"; then
                ((SKIPPED_FILES++))
                continue
            fi
            
            # Determine destination
            local dest_folder
            if [[ "$extension_lower" == "arw" ]]; then
                dest_folder="$arw_folder"
            else
                dest_folder="$jpg_folder"
            fi
            
            # Organize by date if enabled
            if [ "$ORGANIZE_BY_DATE" = true ]; then
                local photo_date
                case "$DATE_FORMAT" in
                    "readable")
                        photo_date=$(get_human_readable_date "$file_path")
                        ;;
                    "simple")
                        photo_date=$(get_exif_date "$file_path")
                        ;;
                    "compact")
                        if command -v exiftool &> /dev/null; then
                            photo_date=$(exiftool -d "%Y%m%d" -DateTimeOriginal -s -s -s "$file_path" 2>/dev/null || stat -f%Sm -t%Y%m%d "$file_path" 2>/dev/null || echo "unknown")
                        else
                            photo_date=$(stat -f%Sm -t%Y%m%d "$file_path" 2>/dev/null || echo "unknown")
                        fi
                        ;;
                    *)
                        photo_date=$(get_human_readable_date "$file_path")
                        ;;
                esac
                dest_folder="$dest_folder/$photo_date"
                if [ "$DRY_RUN" = false ]; then
                    mkdir -p "$dest_folder"
                fi
            fi
            
            # Add to copy list
            echo "$file_path|$dest_folder" >> "$temp_file_list"
        fi
    done < <(find "$CAMERA_MOUNT_PATH" -type f \( $find_pattern \) -print0)
    
    # Clear progress line
    [ "$PROGRESS_BAR" = true ] && echo
    
    local files_to_copy=$(wc -l < "$temp_file_list" | tr -d ' ')
    
    # Display summary
    print_status "Analysis complete:"
    print_status "  - Total files found: $TOTAL_FILES"
    print_status "  - Files to copy: $files_to_copy"
    print_status "  - Files to skip: $SKIPPED_FILES"
    
    if [ "$files_to_copy" -eq 0 ]; then
        if [ "$SKIPPED_FILES" -gt 0 ]; then
            print_success "All files already exist locally - nothing new to copy!"
        else
            print_warning "No files found matching criteria"
        fi
        return 0
    fi
    
    if [ "$DRY_RUN" = true ]; then
        print_status "DRY RUN MODE - No files will be copied"
        print_status "Files that would be copied:"
        cat "$temp_file_list" | while IFS='|' read -r source dest; do
            echo "  $(basename "$source") -> $dest"
        done
        return 0
    fi
    
    # Copy files
    print_status "Starting file copy process..."
    copy_files_parallel "$temp_file_list" "$jpg_folder" "$arw_folder"
    
    # Final statistics
    local end_time=$(date +%s)
    local duration=$((end_time - START_TIME))
    
    print_success "Photo copy completed!"
    print_status "Statistics:"
    print_status "  - Files copied: $COPIED_FILES ($JPG_COPIED JPG + $RAW_COPIED RAW)"
    print_status "  - Files skipped: $SKIPPED_FILES"
    print_status "  - Files failed: $FAILED_FILES"
    print_status "  - Data transferred: $(format_bytes $BYTES_COPIED)"
    print_status "  - Time elapsed: ${duration}s"
    
        if [ "$COPIED_FILES" -gt 0 ]; then
            if [ "$duration" -gt 0 ]; then
                print_status "  - Average speed: $(format_bytes $((BYTES_COPIED / duration)))/s"
            else
                print_status "  - Average speed: $(format_bytes $BYTES_COPIED)/s (instant)"
            fi
            print_status "  - JPG files saved in: $jpg_folder"
            print_status "  - RAW files saved in: $arw_folder"
        fi
    
    # Save configuration
    save_config
}

# Usage and help
usage() {
    cat << EOF
$SCRIPT_NAME v$SCRIPT_VERSION

Usage: $0 [OPTIONS] [CAMERA_PATH]

Copy photos from Sony camera to local storage with advanced optimizations.

OPTIONS:
  -h, --help              Show this help
  -v, --verbose           Enable verbose output
  -q, --quick             Quick mode (minimal checks)
  -n, --dry-run           Preview without copying
  --no-new-only           Copy all files (ignore duplicates)
  --no-parallel           Disable parallel processing
  --no-rsync              Use cp instead of rsync
  --no-verify             Skip integrity verification
  --organize-by-date      Organize photos by date taken
  --date-format=FORMAT    Date format for folders: readable, simple, compact
                          readable: 2023-12-25_Dec (default)
                          simple:   2023-12-25
                          compact:  20231225
  --jpg-only              Copy only JPG files
  --raw-only              Copy only RAW files
  --days=N                Only copy files newer than N days
  --min-size=BYTES        Minimum file size to copy
  --max-size=BYTES        Maximum file size to copy
  --jobs=N                Number of parallel jobs (default: 4)
  --bandwidth=LIMIT       Bandwidth limit for rsync (KB/s)
  --retry=N               Retry count for failed transfers
  --no-progress           Disable progress bar
  --checksum              Create and verify checksums
  --flatten               Flatten directory structure
  --save-config           Save current settings as defaults

EXAMPLES:
  $0                                          # Basic copy with defaults
  $0 --dry-run                               # Preview what would be copied
  $0 --jpg-only --days=7                     # Copy only JPG files from last week
  $0 --organize-by-date --checksum           # Organize by date with verification
  $0 --organize-by-date --date-format=simple # Use simple date format (2023-12-25)
  $0 --organize-by-date --date-format=readable # Use readable format (2023-12-25_Dec)
  $0 /Volumes/SonyA6400/DCIM/101MSDCF        # Use different camera folder

CONFIGURATION:
  Settings are saved in: $CONFIG_FILE
  
EOF
}

# Load configuration first, then allow command-line overrides
load_config

# Input validation
validate_inputs() {
    # Validate parallel jobs - check for empty/non-numeric values
    if [[ ! "$PARALLEL_JOBS" =~ ^[0-9]+$ ]] || [ -z "$PARALLEL_JOBS" ]; then
        print_error "Invalid jobs count: '$PARALLEL_JOBS'. Must be a positive integer."
        exit 1
    fi
    
    if [ "$PARALLEL_JOBS" -le 0 ]; then
        print_error "Invalid jobs count: $PARALLEL_JOBS. Must be a positive integer."
        exit 1
    fi
    
    if [ "$PARALLEL_JOBS" -gt 20 ]; then
        print_warning "High job count ($PARALLEL_JOBS) may overwhelm system resources. Consider using 8 or fewer."
    fi
    
    # Validate days filter - check for empty/non-numeric values
    if [[ ! "$DAYS_FILTER" =~ ^[0-9]+$ ]] || [ -z "$DAYS_FILTER" ]; then
        print_error "Invalid days filter: '$DAYS_FILTER'. Must be 0 or a positive integer."
        exit 1
    fi
    
    if [ "$DAYS_FILTER" -lt 0 ]; then
        print_error "Invalid days filter: $DAYS_FILTER. Must be 0 or positive."
        exit 1
    fi
    
    # Validate file sizes - check for empty/non-numeric values
    if [[ ! "$MIN_FILE_SIZE" =~ ^[0-9]+$ ]] || [ -z "$MIN_FILE_SIZE" ]; then
        print_error "Invalid minimum file size: '$MIN_FILE_SIZE'. Must be 0 or a positive integer."
        exit 1
    fi
    
    if [[ ! "$MAX_FILE_SIZE" =~ ^[0-9]+$ ]] && [ "$MAX_FILE_SIZE" != "0" ] && [ -n "$MAX_FILE_SIZE" ]; then
        print_error "Invalid maximum file size: '$MAX_FILE_SIZE'. Must be 0 or a positive integer."
        exit 1
    fi
    
    if [ "$MIN_FILE_SIZE" -lt 0 ]; then
        print_error "Invalid minimum file size: $MIN_FILE_SIZE. Must be 0 or positive."
        exit 1
    fi
    
    if [ -n "$MAX_FILE_SIZE" ] && [ "$MAX_FILE_SIZE" -lt 0 ]; then
        print_error "Invalid maximum file size: $MAX_FILE_SIZE. Must be 0 or positive."
        exit 1
    fi
    
    if [ "$MAX_FILE_SIZE" -gt 0 ] && [ "$MIN_FILE_SIZE" -gt "$MAX_FILE_SIZE" ]; then
        print_error "Minimum file size ($MIN_FILE_SIZE) cannot be greater than maximum file size ($MAX_FILE_SIZE)."
        exit 1
    fi
    
    # Validate file type selection logic
    if [ "$COPY_JPG" = false ] && [ "$COPY_RAW" = false ]; then
        print_error "Cannot disable both JPG and RAW file copying. At least one file type must be enabled."
        exit 1
    fi
}

# Command line argument parsing
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -q|--quick)
            QUICK_MODE=true
            VERIFY_INTEGRITY=false
            PROGRESS_BAR=false
            shift
            ;;
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        --no-new-only)
            COPY_ONLY_NEW=false
            shift
            ;;
        --no-parallel)
            USE_PARALLEL=false
            shift
            ;;
        --no-rsync)
            USE_RSYNC=false
            shift
            ;;
        --no-verify)
            VERIFY_INTEGRITY=false
            shift
            ;;
        --organize-by-date)
            ORGANIZE_BY_DATE=true
            shift
            ;;
        --date-format=*)
            DATE_FORMAT="${1#*=}"
            if [[ ! "$DATE_FORMAT" =~ ^(readable|simple|compact)$ ]]; then
                print_error "Invalid date format: $DATE_FORMAT. Use: readable, simple, or compact"
                exit 1
            fi
            shift
            ;;
        --jpg-only)
            COPY_JPG=true
            COPY_RAW=false
            shift
            ;;
        --raw-only)
            COPY_JPG=false
            COPY_RAW=true
            shift
            ;;
        --days=*)
            DAYS_FILTER="${1#*=}"
            shift
            ;;
        --min-size=*)
            MIN_FILE_SIZE="${1#*=}"
            shift
            ;;
        --max-size=*)
            MAX_FILE_SIZE="${1#*=}"
            shift
            ;;
        --jobs=*)
            PARALLEL_JOBS="${1#*=}"
            shift
            ;;
        --bandwidth=*)
            BANDWIDTH_LIMIT="${1#*=}"
            shift
            ;;
        --retry=*)
            RETRY_COUNT="${1#*=}"
            shift
            ;;
        --no-progress)
            PROGRESS_BAR=false
            shift
            ;;
        --checksum)
            CREATE_CHECKSUM=true
            shift
            ;;
        --flatten)
            FLATTEN_STRUCTURE=true
            shift
            ;;
        --save-config)
            save_config
            print_success "Configuration saved to $CONFIG_FILE"
            exit 0
            ;;
        /*)
            CAMERA_MOUNT_PATH="$1"
            shift
            ;;
        *)
            print_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate inputs before running
validate_inputs

# Run main function
main
