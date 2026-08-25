#!/bin/bash

# Define colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' 

echo -e "${BLUE}--- Methodist Church in Kenya: Report Generator ---${NC}"

# 1. ACTIVATE CONDA
source ~/miniforge3/etc/profile.d/conda.sh
conda activate tools

# 2. ARGUMENT LOGIC
# Usage: bash generate_report.sh [start_date] [end_date] [send_email]
# Example: bash generate_report.sh 2026-03-01 2026-03-31 yes

START_DATE=$1
END_DATE=$2
SEND_EMAIL=$3

if [ -z "$START_DATE" ] || [ -z "$END_DATE" ]; then
    echo -e "No dates provided. ${GREEN}Defaulting to current month...${NC}"
    START_DATE=""
    END_DATE=""
fi

# 3. RUN GENERATOR
echo -e "${RED}Cleaning logs and generating PDF...${NC}"
rm -f logs/*
echo -e "${GREEN}Logs cleaned...${NC}"
python scripts/python/run_report.py "$START_DATE" "$END_DATE" > /dev/null

# 4. CONDITIONAL EMAIL DISPATCH
if [ "$SEND_EMAIL" == "yes" ]; then
    RECEIPIENTS="clement.mwagwabi@outlook.com,nyiroclement2000@gmail.com"
    CC="nyiroclement2000@gmail.com"
    # RECEIPIENTS="robert.mwagwabi@live.com,maclean5566@gmail.com,"
    # CC="nyiroclement2000@gmail.com"
    LATEST_PDF=$(ls -t output/pdf/*.pdf 2>/dev/null | head -1)

    if [ -f "$LATEST_PDF" ]; then
        echo -e "${BLUE}Dispatching report to Finance Committee...${NC}"
        python scripts/python/send_report.py "$RECEIPIENTS" "$CC" "$LATEST_PDF"
    else
        echo -e "${RED}Error: PDF not found. Email not sent.${NC}"
    fi
else
    echo -e "${GREEN}Email skip requested (Argument 3 was not 'yes').${NC}"
fi

# 5. WRAP UP
LATEST_PDF=$(ls -t output/pdf/*.pdf 2>/dev/null | head -1)
if [ -f "$LATEST_PDF" ]; then
    echo -e "${BLUE}Opening: $LATEST_PDF${NC}"
    open "$LATEST_PDF"
fi

conda deactivate
echo -e "${BLUE}Process Complete.${NC}"