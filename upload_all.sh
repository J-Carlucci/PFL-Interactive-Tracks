#!/usr/bin/env bash

set -Eeuo pipefail

# ============================================================
# SETTINGS
# ============================================================

REPO_DIR="$HOME/PFL-Interactive-Tracks"

# Number of new SST images per commit.
# Reduce this if an SST push is still too large.
SST_BATCH_SIZE=500


# ============================================================
# ERROR HANDLING
# ============================================================

trap '
echo ""
echo "============================================================"
echo "UPLOAD STOPPED"
echo "============================================================"
echo "A command failed or the connection was interrupted."
echo ""
echo "Files and successful GitHub uploads have not been deleted."
echo "Reconnect to the internet and run this script again."
echo "============================================================"
' ERR


# ============================================================
# HELPER FUNCTION
# ============================================================

commit_and_push() {
    local message="$1"
    shift

    git add -A -- "$@"

    if git diff --cached --quiet; then
        echo "No changes found — skipping."
        return 0
    fi

    git commit -m "$message"
    git push origin main

    echo "Successfully uploaded: $message"
    echo ""
}


# ============================================================
# OPEN REPOSITORY
# ============================================================

cd "$REPO_DIR"

echo "============================================================"
echo "PFL INTERACTIVE TRACKS BULK UPLOAD"
echo "============================================================"
echo "Repository: $REPO_DIR"
echo ""

echo "Checking GitHub..."
git fetch origin


# ============================================================
# RECOVER FROM FAILED LOCAL COMMITS
# ============================================================

echo ""
echo "Resetting local commit history to GitHub's current main branch..."
echo "All working files will be preserved."

# This removes failed/unpushed commit records but DOES NOT delete
# the files involved in those commits.
git reset --mixed origin/main

echo "Local failed commits cleared."
echo ""


# ============================================================
# UPLOAD ROOT HTML FILES
# ============================================================

echo "============================================================"
echo "Uploading HTML maps"
echo "============================================================"

commit_and_push \
    "Update HTML maps" \
    ':(top,glob)*.html'


# ============================================================
# UPLOAD EACH *_files DEPENDENCY DIRECTORY
# ============================================================

echo "============================================================"
echo "Uploading HTML dependency directories"
echo "============================================================"

dependency_total=$(
    find . \
        -mindepth 1 \
        -maxdepth 1 \
        -type d \
        -name '*_files' |
    wc -l
)

dependency_number=0

while IFS= read -r -d '' dependency_dir; do
    dependency_number=$((dependency_number + 1))

    dependency_dir="${dependency_dir#./}"
    dependency_name="${dependency_dir%_files}"

    echo ""
    echo "Dependency directory $dependency_number of $dependency_total"
    echo "Processing: $dependency_dir"

    commit_and_push \
        "Add dependencies for map $dependency_name" \
        "$dependency_dir"

done < <(
    find . \
        -mindepth 1 \
        -maxdepth 1 \
        -type d \
        -name '*_files' \
        -print0
)


# ============================================================
# UPLOAD NEW SST FILES IN BATCHES
# ============================================================

echo "============================================================"
echo "Uploading new shared SST imagery"
echo "Batch size: $SST_BATCH_SIZE files"
echo "============================================================"

sst_batch=()
sst_batch_number=1
sst_file_total=0

upload_sst_batch() {
    if [ "${#sst_batch[@]}" -eq 0 ]; then
        return 0
    fi

    echo ""
    echo "Uploading SST batch $sst_batch_number"
    echo "Files in batch: ${#sst_batch[@]}"

    git add -- "${sst_batch[@]}"

    if ! git diff --cached --quiet; then
        git commit -m "Add shared SST imagery batch $sst_batch_number"
        git push origin main
    fi

    sst_file_total=$((sst_file_total + ${#sst_batch[@]}))
    sst_batch_number=$((sst_batch_number + 1))
    sst_batch=()
}

if [ -d "glorys/sst" ]; then

    while IFS= read -r -d '' sst_file; do
        sst_batch+=("$sst_file")

        if [ "${#sst_batch[@]}" -ge "$SST_BATCH_SIZE" ]; then
            upload_sst_batch
        fi

    done < <(
        git ls-files \
            --others \
            --exclude-standard \
            -z \
            -- glorys/sst
    )

    # Upload the final partial batch.
    upload_sst_batch

    echo ""
    echo "New SST files processed: $sst_file_total"

    # Handle changed or deleted SST files that Git already tracks.
    echo "Checking for modified or deleted SST files..."

    git add -u -- glorys/sst

    if ! git diff --cached --quiet; then
        git commit -m "Update shared SST imagery"
        git push origin main
    else
        echo "No tracked SST files require updating."
    fi

else
    echo "The glorys/sst directory was not found — skipping."
fi


# ============================================================
# UPLOAD EACH GLORYS TAG DIRECTORY
# ============================================================

echo ""
echo "============================================================"
echo "Uploading individual GLORYS tag directories"
echo "============================================================"

if [ -d "glorys" ]; then

    tag_total=$(
        find glorys \
            -mindepth 1 \
            -maxdepth 1 \
            -type d \
            ! -name 'sst' |
        wc -l
    )

    tag_number=0

    while IFS= read -r -d '' tag_dir; do
        tag_number=$((tag_number + 1))
        tag_name="$(basename "$tag_dir")"

        echo ""
        echo "Tag $tag_number of $tag_total"
        echo "Processing: $tag_name"

        commit_and_push \
            "Update GLORYS assets for tag $tag_name" \
            "$tag_dir"

    done < <(
        find glorys \
            -mindepth 1 \
            -maxdepth 1 \
            -type d \
            ! -name 'sst' \
            -print0
    )

else
    echo "The glorys directory was not found — skipping tag assets."
fi


# ============================================================
# UPLOAD ALL OTHER TOP-LEVEL FILES AND DIRECTORIES
# ============================================================

echo ""
echo "============================================================"
echo "Checking all remaining repository files"
echo "============================================================"

while IFS= read -r -d '' item; do
    item="${item#./}"
    item_name="$(basename "$item")"

    # Already handled elsewhere.
    case "$item_name" in
        .git)
            continue
            ;;
        glorys)
            continue
            ;;
        *_files)
            continue
            ;;
        *.html)
            continue
            ;;
    esac

    echo ""
    echo "Checking: $item"

    commit_and_push \
        "Update $item_name" \
        "$item"

done < <(
    find . \
        -mindepth 1 \
        -maxdepth 1 \
        ! -name '.git' \
        -print0
)


# ============================================================
# FINAL CHECK
# ============================================================

echo ""
echo "============================================================"
echo "Final repository check"
echo "============================================================"

git status --short

if [ -n "$(git status --porcelain)" ]; then
    echo ""
    echo "Some files remain uncommitted."
    echo "Review the list above before staging them."
else
    echo ""
    echo "Working directory is clean."
fi

echo ""
echo "============================================================"
echo "ALL AVAILABLE UPLOADS COMPLETED SUCCESSFULLY"
echo "============================================================"
