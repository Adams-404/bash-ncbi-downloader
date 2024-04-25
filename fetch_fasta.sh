#!/bin/bash

source config/ncbi_endpoints.conf

if [ -z "$1" ]; then
    echo "Usage: $0 <ACCESSION_ID>"
    exit 1
fi

ACCESSION=$1
URL="${API_URL}?db=nuccore&id=${ACCESSION}&rettype=fasta&retmode=text"

echo "Downloading accession ${ACCESSION} from ${API_URL}..."
curl -s "$URL" -o "${ACCESSION}.fasta"

if [ -f "${ACCESSION}.fasta" ]; then
    ./bin/validate_sequence.sh "${ACCESSION}.fasta"
    if [ $? -eq 0 ]; then
        ./bin/parse_headers.awk "${ACCESSION}.fasta"
    else
        echo "Error: Sequence validation failed."
        rm -f "${ACCESSION}.fasta"
    fi
else
    echo "Error: Failed to fetch sequence."
fi
