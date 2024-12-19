# ncbi fasta sequence downloader

this repository contains a dynamic shell script pipeline that automates downloading sequence FASTA records directly from public NCBI nucleotide databases.

## file structure

this repository features a modular pipeline layout:
- `fetch_fasta.sh`: entry point script coordinating endpoint downloads, validations, and scraps
- `config/ncbi_endpoints.conf`: parameter definitions for API URLs
- `bin/validate_sequence.sh`: validator script checking FASTA headers formatting
- `bin/parse_headers.awk`: AWK script parsing and printing FASTA details

## execution

make script pipelines executable:

```bash
chmod +x fetch_fasta.sh bin/validate_sequence.sh bin/parse_headers.awk
```

download sequence:

```bash
./fetch_fasta.sh <ACCESSION_ID>
```

## challenges and lessons

handling curls fallback status codes was highly educational. i implemented dynamic validations passing output returns to my validator shell script to guarantee the file exists and is valid before executing my AWK parsers. it works perfectly!
