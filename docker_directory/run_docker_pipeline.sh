#!/usr/bin/env bash
set -e   # Halt on first failure

START_DATE=$1
END_DATE=$2

# Everything is now entirely contained within docker_directory
DOCKER_DIR="/home/cozmopol/projects/church_finance/circuit_finance/docker_directory"
PIPELINE_DIR="$DOCKER_DIR/pipeline_data"

echo "🚀 Starting Docker Pipeline for $START_DATE to $END_DATE..."

# 1. Clean the old pipeline data
rm -rf "$PIPELINE_DIR/exports/"* "$PIPELINE_DIR/table/"* "$PIPELINE_DIR/plots/"*

# Create the clean organizational structure
mkdir -p "$PIPELINE_DIR/exports" "$PIPELINE_DIR/table" "$PIPELINE_DIR/plots"
mkdir -p "$PIPELINE_DIR/output/pdf" "$PIPELINE_DIR/output/csv" "$PIPELINE_DIR/logs"

# 2. Run Phase 1: Python Ledger
echo ">>> Running python-ledger..."
docker build -t python-ledger -f Dockerfile.python-ledger .
docker run --rm --network host -v "$PIPELINE_DIR:/data" python-ledger "$START_DATE" "$END_DATE"

# 3. Run Phase 2: R Plotter
echo ">>> Running r-plotter..."
docker build -t r-plotter -f Dockerfile.r-plotter .
docker run --rm -v "$PIPELINE_DIR:/data" r-plotter "$START_DATE" "$END_DATE"

# 4. Run Phase 3: LaTeX Builder (dumps everything into /data/output temporarily)
echo ">>> Running latex-builder..."
docker build -t latex-builder -f Dockerfile.latex-builder .
docker run --rm --network host -v "$PIPELINE_DIR:/data" latex-builder "$START_DATE" "$END_DATE"

# 5. The Cleanup Crew: Sort the files into their proper folders
echo ">>> Organizing files..."
mv "$PIPELINE_DIR/output/"*.pdf "$PIPELINE_DIR/output/pdf/" 2>/dev/null || true
mv "$PIPELINE_DIR/output/"*.log "$PIPELINE_DIR/output/"*.aux "$PIPELINE_DIR/logs/" 2>/dev/null || true

echo "✅ Pipeline Complete! PDF is ready for dispatch."