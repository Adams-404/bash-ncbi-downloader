# NCBI FASTA Sequence Downloader

A modular Bash pipeline that automates downloading, validating, and inspecting nucleotide FASTA records directly from NCBI's public E-utilities API (`efetch.fcgi`). Given an NCBI accession ID, the pipeline fetches the raw FASTA file, validates its header formatting, and pretty-prints header metadata to stdout.

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Project Tree](#project-tree)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Configuration](#configuration)
- [How It Works](#how-it-works)
- [File Breakdown](#file-breakdown)
- [How to Run](#how-to-run)
- [Example Session](#example-session)
- [Validation & Parsing Details](#validation--parsing-details)
- [Error Handling & Exit Codes](#error-handling--exit-codes)
- [Ignored Files](#ignored-files)
- [Troubleshooting](#troubleshooting)
- [Challenges and Lessons Learned](#challenges-and-lessons-learned)
- [Future Improvements](#future-improvements)

## Overview

This repository implements a 3-stage shell pipeline:

1.  **Fetch** — `curl` download of `rettype=fasta&retmode=text` from NCBI E-utilities.
2.  **Validate** — `grep`-based FASTA header check via `bin/validate_sequence.sh`.
3.  **Parse** — `AWK` header inspection via `bin/parse_headers.awk`.

All endpoint URLs are externalized into `config/ncbi_endpoints.conf` so the pipeline can be retargeted (e.g., to a mock server for testing or to `retmode=xml`) without editing logic.

> **Primary Entry Point:** `fetch_fasta.sh:1`

## Features

- Single-argument interface: `./fetch_fasta.sh <ACCESSION_ID>`
- Config-driven API endpoint (`config/ncbi_endpoints.conf:1`)
- Atomic validation before parsing — invalid/empty downloads are deleted automatically (`fetch_fasta.sh:20-23`)
- Human-readable header output (`bin/parse_headers.awk:2-5`)
- Zero external dependencies beyond `bash`, `curl`, `awk`, `grep`, `head`
- Works on any POSIX-like system (Linux, macOS, WSL)

## Project Tree

Generated via `tree` (fallback `find . -print | sort`):

```text
.
├── bin
│   ├── parse_headers.awk        # AWK header parser (5 lines)
│   └── validate_sequence.sh     # FASTA validator (10 lines)
├── config
│   └── ncbi_endpoints.conf      # API_URL definition (1 line)
├── fetch_fasta.sh               # Orchestrator / entry point (26 lines)
├── .gitignore                   # Ignores *.fasta, *.log artifacts
└── README.md                    # This file

3 directories, 5 files
```

Directory purposes:

| Path | Purpose |
|------|---------|
| `fetch_fasta.sh` | Orchestrates URL construction, `curl` download, validation gating, and parsing |
| `config/ncbi_endpoints.conf` | Single source of truth for NCBI base URL |
| `bin/validate_sequence.sh` | Exit-code-based validator (`0` = valid, `1` = invalid) |
| `bin/parse_headers.awk` | Prints every `>` header line with formatting |
| `*.fasta` (generated, ignored) | Per-accession download output: `<ACCESSION>.fasta` |

## Prerequisites

| Tool | Minimum Version (tested) | Purpose | Check |
|------|--------------------------|---------|-------|
| `bash` | 5.3.9 | Orchestrator shell | `bash --version` |
| `curl` | 8.18.0 | HTTPS fetch of FASTA | `curl --version` |
| `awk` (gawk) | 5.3.2 | Header parsing | `awk --version` |
| `grep` | 3.12 | Header validation | `grep --version` |
| `head` | coreutils | Read first line for validation | `head --version` |
| Internet | — | Reach `eutils.ncbi.nlm.nih.gov` | `ping -c1 eutils.ncbi.nlm.nih.gov` |

> No `conda`, `pip`, or NCBI API key required for public `efetch` (anonymous requests are rate-limited; for bulk downloads request an API key and add `&api_key=YOUR_KEY` to the URL in `fetch_fasta.sh:11`).

## Installation

1. Clone the repository:

   ```bash
   git clone <REPO_URL>
   cd bash-ncbi-downloader
   ```

2. Make the pipeline executable:

   ```bash
   chmod +x fetch_fasta.sh bin/validate_sequence.sh bin/parse_headers.awk
   ```

3. Verify executability:

   ```bash
   ls -l fetch_fasta.sh bin/validate_sequence.sh bin/parse_headers.awk
   # Expected: -rwxr-xr-x for each
   ```

## Configuration

All endpoint configuration lives in one file:

```bash
# config/ncbi_endpoints.conf:1
API_URL="https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi"
```

- Sourced at runtime via `fetch_fasta.sh:3` (`source config/ncbi_endpoints.conf`).
- To switch to a different NCBI database or add parameters, edit only this file. The pipeline composes the final URL at `fetch_fasta.sh:11`:

  ```bash
  URL="${API_URL}?db=nuccore&id=${ACCESSION}&rettype=fasta&retmode=text"
  # db=nuccore  → nucleotide database
  # rettype=fasta → FASTA format
  # retmode=text  → plain text (not XML/JSON)
  ```

- **Testing / Mocking:** Point `API_URL` to a local HTTP server (e.g., `http://localhost:8000/efetch.fcgi`) to run offline tests without hitting NCBI.

## How It Works

### Pipeline Flow (ASCII)

```text
 User
  │
  │  ./fetch_fasta.sh NM_000546
  ▼
 fetch_fasta.sh:5-8 ──► [arg check] ── empty? ──► echo Usage && exit 1
  │
  │  ACCESSION=NM_000546
  ▼
 fetch_fasta.sh:11 ──► URL = ${API_URL}?db=nuccore&id=NM_000546&rettype=fasta&retmode=text
  │
  ▼
 fetch_fasta.sh:13-14 ──► curl -s "$URL" -o "NM_000546.fasta"
  │
  ▼
 fetch_fasta.sh:16 ──► [ -f "NM_000546.fasta" ] ? ── no ──► echo "Failed to fetch"
  │
  yes
  ▼
 fetch_fasta.sh:17 ──► ./bin/validate_sequence.sh "NM_000546.fasta"
  │                         │
  │                         ├─► head -n 1 "$1" | grep -q "^>"  (validate_sequence.sh:6)
  │                         ├─► match ──► exit 0 (valid)
  │                         └─► no match ──► exit 1 (invalid)
  │
  ▼
 fetch_fasta.sh:18 ──► [ $? -eq 0 ] ?
  │                         │
  │                    yes  │  no
  │                     ▼      ▼
  │         bin/parse_headers.awk    echo "Sequence validation failed."
  │         (prints headers)         rm -f "${ACCESSION}.fasta"
  ▼
 Done ──► NM_000546.fasta on disk + stdout header summary
```

### Step-by-Step Walkthrough

| Step | File:Line | Action | Detail |
|------|-----------|--------|--------|
| 1 | `fetch_fasta.sh:1` | Shebang | `#!/bin/bash` ensures Bash semantics (not `sh`) |
| 2 | `fetch_fasta.sh:3` | Load config | `source config/ncbi_endpoints.conf` injects `API_URL` into env |
| 3 | `fetch_fasta.sh:5-8` | Argument guard | If `$1` empty, prints `Usage: $0 <ACCESSION_ID>` and `exit 1` |
| 4 | `fetch_fasta.sh:10` | Capture input | `ACCESSION=$1` (no sanitization beyond shell quoting) |
| 5 | `fetch_fasta.sh:11` | Build URL | Interpolates accession into E-utilities query string |
| 6 | `fetch_fasta.sh:13-14` | Download | `curl -s "$URL" -o "${ACCESSION}.fasta"` — silent mode, writes to `<ACCESSION>.fasta` in CWD; `echo` at line 13 logs intention before curl |
| 7 | `fetch_fasta.sh:16` | Existence check | `if [ -f "${ACCESSION}.fasta" ]` — catches curl write failures/permissions |
| 8 | `fetch_fasta.sh:17-18` | Validation gate | Executes validator, checks `$? -eq 0`. Validator exit code is the sole control signal — no stdout parsing |
| 9 | `fetch_fasta.sh:19` | Parse | On success, `./bin/parse_headers.awk "${ACCESSION}.fasta"` prints header details |
| 10 | `fetch_fasta.sh:20-23` | Cleanup on invalid | On validation failure, error message + `rm -f` removes corrupt/empty file so next run is clean |
| 11 | `fetch_fasta.sh:24-26` | Fallback | If file never created, `Error: Failed to fetch sequence.` |

## File Breakdown

### 1. `fetch_fasta.sh` — 26 lines

Entry point. Responsibilities: config loading, CLI parsing, URL templating, curl I/O, and branching on validator exit code. All side effects (file creation, deletion) happen here. Relative paths (`config/...`, `bin/...`) assume execution from repo root.

Key snippet:

```bash
# fetch_fasta.sh:11-14
URL="${API_URL}?db=nuccore&id=${ACCESSION}&rettype=fasta&retmode=text"
echo "Downloading accession ${ACCESSION} from ${API_URL}..."
curl -s "$URL" -o "${ACCESSION}.fasta"
```

### 2. `config/ncbi_endpoints.conf` — 1 line

```bash
API_URL="https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi"
```

Sourced, not executed. Keep quoting intact. No trailing slash handling needed because `fetch_fasta.sh:11` prepends `?`.

### 3. `bin/validate_sequence.sh` — 10 lines

Minimal validator. Reads **only first line** (`head -n 1`) and tests for FASTA header prefix `^>`.

```bash
# bin/validate_sequence.sh:6-10
if head -n 1 "$1" | grep -q "^>"; then
    exit 0
else
    exit 1
fi
```

- `grep -q` — quiet; no output, just exit code.
- Returns `0` (valid) if first char is `>`, `1` otherwise (covers NCBI error XML/HTML, empty files, network errors).
- Usage guard at `:2-5` handles missing argument.

### 4. `bin/parse_headers.awk` — 5 lines

```awk
#!/usr/bin/awk -f
/^>/ {
    print "FASTA Accession Header Details:"
    print "  " substr($0, 2)
}
```

- Pattern `/^>/` matches any header line (FASTA allows multi-line sequences with multiple headers in concatenated files).
- `substr($0, 2)` strips leading `>` for cleaner display.
- Invoked as `./bin/parse_headers.awk file.fasta` (shebang `awk -f`). Alternatively callable as `awk -f bin/parse_headers.awk file.fasta`.

### 5. `.gitignore` — 2 lines

```gitignore
*.fasta
*.log
```

Prevents accidental commits of downloaded sequences and logs. See [Ignored Files](#ignored-files).

## How to Run

### Quick Start

```bash
chmod +x fetch_fasta.sh bin/validate_sequence.sh bin/parse_headers.awk
./fetch_fasta.sh NM_000546
```

### Find an Accession ID

1. Go to https://www.ncbi.nlm.nih.gov/nuccore/
2. Search a gene/organism (e.g., `BRCA1 human` or `SARS-CoV-2`).
3. Copy the **Accession** (e.g., `NM_000546` for human TP53 mRNA, `NC_045512` for SARS-CoV-2, `NR_046233` for a non-coding RNA).
4. Paste as the sole argument.

### Valid Accession Examples to Try

| Accession | Description | Expected Header Prefix |
|-----------|-------------|------------------------|
| `NM_000546` | *H. sapiens* TP53 mRNA | `>NM_000546.6 Homo sapiens tumor protein p53 ...` |
| `NC_000001` | *H. sapiens* chromosome 1 (large — slow) | `>NC_000001.11 ...` |
| `NR_046233` | Small non-coding | `>NR_046233.1 ...` |
| `INVALID123` | Negative test | Triggers validation failure + deletion |

### Output

- **File on disk:** `<ACCESSION>.fasta` in the directory where you invoked the script (e.g., `NM_000546.fasta`).
- **Stdout:**

  ```text
  Downloading accession NM_000546 from https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi...
  FASTA Accession Header Details:
    NM_000546.6 Homo sapiens tumor protein p53 (TP53), mRNA
  ```

- **FASTA file content (first 2 lines):**

  ```text
  >NM_000546.6 Homo sapiens tumor protein p53 (TP53), mRNA
  ATGGAGGAGCCGCAGTCAGATCCTAGCGTCGAGCCCCCTCTGAGTCAGGAAAC...
  ```

### Running Validator / Parser Standalone

```bash
# Validate any existing FASTA:
./bin/validate_sequence.sh NM_000546.fasta; echo $?   # 0 = valid

# Parse without re-downloading:
./bin/parse_headers.awk NM_000546.fasta
# or
awk -f bin/parse_headers.awk NM_000546.fasta

# Validate + parse manually:
./bin/validate_sequence.sh myfile.fasta && ./bin/parse_headers.awk myfile.fasta
```

### Batch Download (one-liner)

```bash
for acc in NM_000546 NR_046233 NM_007294; do ./fetch_fasta.sh "$acc"; done
```

## Validation & Parsing Details

- **Validation is header-only** (`validate_sequence.sh:6`): Checks that byte 0 of the file is `>`. Does not verify nucleotide alphabet (`ACGTN`), sequence length, or that the accession inside the header matches the requested one. This is intentional for speed and to catch NCBI error responses like:
  ```xml
  <?xml version="1.0"?>
  <eFetchResult>...</eFetchResult>
  ```
  or HTML `429 Too Many Requests` pages which never start with `>`.

- **Parsing is line-oriented** (`parse_headers.awk:2`): Every line matching `/^>/` is echoed. Multi-record FASTA (rare via `efetch` for single id, common if you comma-join ids) will print each header sequentially.

- **No temp files:** Pipeline writes directly to final destination; invalid files are cleaned up synchronously (`fetch_fasta.sh:22`).

## Error Handling & Exit Codes

| Condition | Script | Behavior | Exit Code |
|-----------|--------|----------|-----------|
| No accession argument | `fetch_fasta.sh:5-8` | `echo "Usage: $0 <ACCESSION_ID>"` | `1` |
| `curl` fails to write file | `fetch_fasta.sh:16` branch else | `echo "Error: Failed to fetch sequence."` | `0` (script ends, no file) |
| File exists but header invalid | `bin/validate_sequence.sh:8` → `fetch_fasta.sh:20-23` | `echo "Error: Sequence validation failed."` + `rm -f` | `0` (file deleted) |
| Valid download | `fetch_fasta.sh:19` | Prints headers, retains `.fasta` | `0` |
| Validator called without arg | `validate_sequence.sh:2-5` | `echo "Usage: $0 <FILE>"` | `1` |

> **Note:** `curl -s` suppresses progress but does **not** fail on HTTP error codes by itself. A `404`/`400` from NCBI still writes a body (often XML/HTML) to the `.fasta` file, which is then caught by the validator. For stricter HTTP handling, replace `curl -s` with `curl -s -f` (fail on HTTP >=400) at `fetch_fasta.sh:14` — but be aware this changes the error path to the `-f` file check rather than validation.

## Ignored Files

`.gitignore:1-2`:

```gitignore
*.fasta   # All downloaded sequences (per-accession files)
*.log     # Optional logs if you redirect: ./fetch_fasta.sh NM_000546 > run.log 2>&1
```

To force-track a reference FASTA (not recommended), use `git add -f <file>.fasta`.

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| `Usage: ./fetch_fasta.sh <ACCESSION_ID>` | Missing argument | Provide an accession: `./fetch_fasta.sh NM_000546` |
| `Error: Sequence validation failed.` | Invalid accession, network returned XML/HTML, or truncated download | Try a known-good accession; check `cat INVALID123.fasta` before it was deleted (or temporarily comment `rm`); verify internet |
| `Error: Failed to fetch sequence.` | `curl` could not write file (permissions, disk full, `API_URL` malformed) | Check `ls -ld .` permissions; `curl -v "$URL"` manually; verify `config/ncbi_endpoints.conf:1` |
| `permission denied: ./fetch_fasta.sh` | Missing `chmod +x` | `chmod +x fetch_fasta.sh bin/validate_sequence.sh` |
| `No such file or directory: config/ncbi_endpoints.conf` | Ran script from outside repo root | `cd /path/to/bash-ncbi-downloader && ./fetch_fasta.sh NM_000546` |
| `awk: cannot open file` | File path typo to `parse_headers.awk` | Use relative path from repo root or `awk -f bin/parse_headers.awk file.fasta` |
| Slow download (`NC_000001`) | Chromosome-scale record (~250 MB) | Expected; test with small mRNAs first (`NM_000546`) |
| `429 Too Many Requests` (file contains HTML) | NCBI rate limit (3 req/s anonymous) | Wait 1–2 sec between requests or add API key to `fetch_fasta.sh:11` |

**Debug tip:** Inspect the raw downloaded file before validation cleanup:

```bash
# Temporarily disable auto-delete for inspection:
# comment out rm -f at fetch_fasta.sh:22, then
./fetch_fasta.sh INVALID123
cat INVALID123.fasta
head -n 1 INVALID123.fasta | od -c   # check first char
```

## Challenges and Lessons Learned

Handling `curl` fallback/status codes was highly educational. `curl -s` alone does not surface HTTP errors, so the pipeline implements **dynamic validations passing output returns to the validator shell script** to guarantee the file exists and is valid before executing the AWK parser (`fetch_fasta.sh:16-19`). Key takeaways:

- **Exit-code contracts** beat stdout parsing: `validate_sequence.sh:6-10` returns only `0`/`1`, letting `fetch_fasta.sh:18` branch cleanly on `$?`.
- **Fail-then-clean**: Invalid artifacts are deleted immediately (`fetch_fasta.sh:22`) to prevent downstream parsers from operating on corrupt data.
- **Config externalization** (`config/ncbi_endpoints.conf:1`) decouples logic from environment — essential for testing against mock endpoints without code changes.
- Small, composable Unix tools (`head` + `grep` for validation, `awk` for parsing) keep each component under 10 lines and independently testable.

## Future Improvements

- Add `curl -f` / `--write-out "%{http_code}"` check at `fetch_fasta.sh:14` for explicit HTTP error handling before validation.
- Support comma-separated accession lists: `./fetch_fasta.sh NM_000546,NM_007294` with looped fetch + concatenated output.
- Add nucleotide alphabet validation (`grep -qvE "^[ACGTNacgtn>]"`) as a second validator stage.
- Optional arguments: `-o <outfile>`, `-d <database>`, `--retmode xml` via `getopts`.
- Rate-limit handling with exponential backoff and API-key injection via env var (`${NCBI_API_KEY}`).
- Add `shellcheck` linting and minimal `bats` test suite for validator/parser.

---

*Pipeline tested on Bash 5.3.9, curl 8.18.0, GNU Awk 5.3.2. For issues, open a GitHub issue with the accession ID and the first 5 lines of the generated `.fasta` (if any).*
