#!/usr/bin/awk -f
/^>/ {
    print "FASTA Accession Header Details:"
    print "  " substr($0, 2)
}
