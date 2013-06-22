#!/bin/bash

# Dump kerning listing from a PFM binary to AFM syntax
# Copyright 2012 Grzegorz Rolek


# Parse and reset the arguments.
set $(getopt e: $*)

# Make sure there are all necessary arguments given.
test $# != 3 && { echo >&2 "usage: $(basename $0) -e <vector.enc> <metrics.pfm>"; exit 2; }

ENC=$1
PFM=$3

# Parse the encoding file for a bare list of glyphs names.
NAMES=($(sed -n 's/^\/\(.*[^ []\)$/\1/p' <$ENC))

# Byte offset to the kerning table is stored as four bytes at byte 131 in a PFM binary.
# PFM binaries have a little-endian byte order; be cautious on big-endian architectures.
# See Adobe's Technical Note #5178, Building PFM files... for a full spec.
OFFSET=$(hexdump -s 131 -n 4 -e '"%u"' $PFM)

# Number of kern pair entries: first 2 bytes of the table.
NO=$(hexdump -s $OFFSET -n 2 -e '/2 "%u"' $PFM)

# Dump the entries as newline-separated "char char value" sequences.
# Entries start at 2 bytes into the table, 4 bytes long each (two chars plus a signed short).
ENTRIES=$(hexdump -s $(($OFFSET + 2)) -n $(($NO * 4)) -e '2/1 "%u " /2 " %i\n"' $PFM)

# Start echoing a kerning listing with the header.
echo "StartKernData"
echo "StartKernPairs $NO"

# Iterate through all the entries.
while read ENTRY
do

	# Split up the entry into a list of appropriate fields.
	LIST=($ENTRY); LEFT=${LIST[0]}; RIGHT=${LIST[1]}; VALUE=${LIST[2]}

	# Echo the kerning pair by glyph names.
	echo "KPX ${NAMES[$LEFT]} ${NAMES[$RIGHT]} $VALUE"

done <<<"$ENTRIES"

# End the listing with a trailer.
echo "EndKernPairs"
echo "EndKernData"

# That's it.
exit
