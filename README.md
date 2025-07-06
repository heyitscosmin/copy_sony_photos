# Sony Photo Copy Script

A simple script to copy photos from Sony cameras with some useful features I built for my own photography workflow.

## What it does

- Copies photos from Sony camera to your computer faster than drag-and-drop
- Automatically organizes photos by date
- Skips files you've already copied to avoid duplicates
- Handles both JPG and RAW (ARW) files
- Can copy multiple files at once for speed

## Quick Start

1. Connect your Sony camera via USB
2. Make the script executable: `chmod +x copy_sony_photos_advanced.sh`
3. Run a dry run first: `./copy_sony_photos_advanced.sh --dry-run`
4. If it looks good, run it for real: `./copy_sony_photos_advanced.sh`

Your photos will be copied to `~/Sony-photos/JPG/` and `~/Sony-photos/ARW/`

## Common Usage

### Copy everything
```bash
./copy_sony_photos_advanced.sh
```

### Copy only today's photos
```bash
./copy_sony_photos_advanced.sh --days=1
```

### Copy only JPG files
```bash
./copy_sony_photos_advanced.sh --jpg-only
```

### Copy only RAW files
```bash
./copy_sony_photos_advanced.sh --raw-only
```

### Organize by date
```bash
./copy_sony_photos_advanced.sh --organize-by-date
```

## Features

### Parallel copying
Copies multiple files at once (default 4, can be changed with `--jobs=N`)

### Duplicate detection
Compares file sizes to skip files you already have

### Date organization
When using `--organize-by-date`, creates folders like:
```
~/Sony-photos/
├── JPG/
│   ├── 2025-07-01_Jul/
│   ├── 2025-07-02_Jul/
│   └── 2025-07-06_Jul/
└── ARW/
    ├── 2025-07-01_Jul/
    ├── 2025-07-02_Jul/
    └── 2025-07-06_Jul/
```

### Safety features
- Verifies files copied correctly
- Continues if individual files fail
- Logs what it's doing

## All Command Options

### Basic usage
```bash
# See what would be copied
./copy_sony_photos_advanced.sh --dry-run

# Copy everything
./copy_sony_photos_advanced.sh

# Get help
./copy_sony_photos_advanced.sh --help
```

### Performance options
```bash
# Use more parallel jobs (default is 4)
./copy_sony_photos_advanced.sh --jobs=8

# Limit bandwidth
./copy_sony_photos_advanced.sh --bandwidth=1000
```

### File filtering
```bash
# Only JPG files
./copy_sony_photos_advanced.sh --jpg-only

# Only RAW files
./copy_sony_photos_advanced.sh --raw-only

# Only files from last 7 days
./copy_sony_photos_advanced.sh --days=7
```

### Organization
```bash
# Organize by date taken
./copy_sony_photos_advanced.sh --organize-by-date

# Different date formats
./copy_sony_photos_advanced.sh --organize-by-date --date-format=simple     # 2025-07-06
./copy_sony_photos_advanced.sh --organize-by-date --date-format=readable   # 2025-07-06_Jul
./copy_sony_photos_advanced.sh --organize-by-date --date-format=compact    # 20250706
```

### Safety options
```bash
# Verify files with checksums
./copy_sony_photos_advanced.sh --checksum

# Quick mode (less verification)
./copy_sony_photos_advanced.sh --quick

# Verbose output
./copy_sony_photos_advanced.sh --verbose
```

## Troubleshooting

### Camera not found
```
[ERROR] Camera mount path not found: /Volumes/SonyA6400/DCIM/100MSDCF
```

1. Check camera is connected and turned on
2. Look in Finder under "Locations" for your camera
3. Try specifying the path: `./copy_sony_photos_advanced.sh /Volumes/YourCamera/DCIM/101MSDCF`

### No new files
```
[SUCCESS] All files already exist locally - nothing new to copy!
```

This is normal - the duplicate detection is working. Use `--verbose` to see what's being skipped.

### Slow performance
Try:
- `--jobs=8` (or higher)
- `--quick` mode
- `--jpg-only` or `--raw-only`

## Requirements

- macOS (primary), Linux should work
- Standard command line tools (already installed on macOS)
- Optional: `exiftool` for better date detection (`brew install exiftool`)

## License

MIT - do whatever you want with it.
