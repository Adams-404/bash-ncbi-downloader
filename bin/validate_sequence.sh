#!/bin/bash
if [ -z "$1" ]; then
    echo "Usage: $0 <FILE>"
    exit 1
fi
if head -n 1 "$1" | grep -q "^>"; then
    exit 0
else
    exit 1
fi
