#!/bin/bash

# Build font difference mappings for and run Adobe's 'mergeFonts' utility
# Copyright 2012-2013 Grzegorz Rolek
#
# Because 'mergeFonts' spits an error for each and every duplicate glyph it encounters in a merge queue,
# make, if necessary, explicit merge maps with those glyphs, that particular font introduces as new in the queue.


USAGE="usage: $(basename $0) <output.pfa> <base.pfa> [[<merge.map>] <merge.pfa> ...]"

# Make sure at least output and source files are given.
test $# -lt 2 && { echo >&2 "$USAGE"; exit 2; }

# Collect the base/output filenames and skip to the fonts to merge.
OUTPUT=$1; BASE=$2; shift 2

# Start making the diffs with a list of glyphs present in the base font file.
SET=$(t1disasm $BASE | sed -n '/^\/\(..*\) {$/s//\1/p')

QUEUE=""

# Iterate through the map-font arguments in a queue.
while test "$1" != ""
do

	# Collect the filenames of a map-font pair and shift the queue for next iteration.
	# If no map argument is given for the font, prepare one with the same base name.
	if test -f $1 && test "$(head -1 $1)" != "mergeFonts"
	then MAP=$(sed 's/\(.*\)\(\.[^.]*$\)/\1.map/' <<<$1); FONT=$1; shift
	else MAP=$1; FONT=$2; shift 2
	fi

	# If there's no pre-prepared map for this font then make one with all the new glyphs the font provides.
	if ! test -f $MAP
	then

		# Extract a glyph list from the font for comparison, and filter glyphs that haven't been introduced already.
		NEW=$(sort -u <<<"$SET" | comm -13 - <(t1disasm $FONT | sed -n '/^\/\(..*\) {$/s//\1/p' | sort -u))

		# Dump properly formatted merge map.
		printf '%s\n' 'mergeFonts' "$NEW" | sed '2,$s/^.*$/& &/' >$MAP

	fi

	# Extend the list of glyphs already included with those in the font's map.
	SET=$(echo "$SET"; sed -e '/^mergeFonts$/d' -e '/^#.*$/d' -e 's/^\(..*\) \1$/\1/' $MAP)

	# Make the font into the queue only if there's anything in particular to merge.
	# This is necessery, because in case of an empty map, 'mergeFonts' takes the whole font as is.
	test $(wc -w <$MAP) -gt 1 && QUEUE=$QUEUE" $MAP $FONT"

done

# Merge the whole queue.
mergeFonts $OUTPUT $BASE $QUEUE

# Exit with status of the merge.
exit $?
