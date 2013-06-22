#!/bin/bash

# Build script for Kontrapunkt Pro project directory
# Copyright 2012 Grzegorz Rolek
#
# This script builds Kontrapunkt Pro OpenType binaries. It makes a readable commentary
# on the whole build process, but for convenience just use 'make' instead.
# Pass into the script any of the 'makeotf' options to extend or override those below.


# Check for critical tools.
for TOOL in t1unmac t1disasm t1asm mergeFonts rotateFont makeotf
do type $TOOL &>/dev/null || { echo >&2 "Fatal: No '$TOOL' found; see README for requirements."; exit 1; }
done

# Clean up existing builds, if any.
rm -rf build && mkdir build

# Iterate through subdirectories of the family styles.
for STYLE in Light LightItalic Bold
do

	# Figure out short style name according to the "5:3:3" rule.
	STY=$(sed 's/\([A-Z][a-z]\{0,2\}\)[a-z]*/\1/g' <<<$STYLE)

	# Paths to base Kontrapunkt family and its derivatives without the various suffixes.
	BASE=Kontrapunkt/$STYLE/Kontr$STY
	CE=KontrapunktCE/$STYLE/KontrCE$STY
	EXPERT=KontrapunktExpert/$STYLE/KontrExp$STY


	# PREPARING THE BASE FONT & KERNING DATA

	# Those Mac-specific fonts store font programs in POST resource forks.
	# They were archived with resource-savvy 'ditto' utility for repository storage.
	test -f $BASE || ditto -x $BASE.cpgz $(dirname $BASE)

	# Encode the forks and dump a raw PostScript Type 1 source for further processing.
	test -f $BASE.ps || macbinary encode -p $BASE | t1unmac -a | t1disasm >$BASE.ps

	# There's apparently no kerning listing in the original ASCII metrics, nor in the FOND resources.
	# Still, there's one in the printer binaries, so take it out and write into a new ASCII metrics file.
	if ! test -f ${BASE}Kern.afm
	then

		# Duplicate the original ASCII metrics into a new file with newlines instead of carriage returns.
		# Note the locale change; this avoids 'tr' failure on some non-ASCII chars in the file.
		LC_CTYPE=C; tr '\r' '\n' <$BASE.afm >${BASE}Kern.afm

		# Insert the listing into the new metrics just after the EndCharMetrics line.
		# Use kerndump.sh with the encoding the binaries were probably generated with originally.
		printf '%s\n' /EndCharMetrics/+1i "$(sh kerndump.sh -e default.enc $BASE.pfm)" . wq | ed -s ${BASE}Kern.afm

	fi


	# MERGING THE EXTENDED CHARSET WITH THE BASE FAMILY

	# Because 'mergeFonts' spits an error for each and every duplicate glyph it encounters in a merge queue,
	# make a merge map for each family with a diff of new glyphs the family introduces.
	# This also makes it possible to use a pre-prepared map and exclude any glyph of the original family,
	# thus letting its duplicate in derived family to be merged in instead.

	# Start making the diffs with a list of glyphs present in the Kontrapunkt Pro font file.
	SET=$(sed -n '/^\/\(..*\) {$/s//\1/p' $STYLE/font.ps)

	for FAMILY in base ce expert
	do

		# Take out an actual path to the font of this particular family.
		eval FONT=\$$(echo $FAMILY | tr 'a-z' 'A-Z')

		# If there's no map for this family or if it's outdated, then make one with all the new glyphs the family provides.
		if ! test -f $STYLE/$FAMILY.map || test -f $STYLE/$FAMILY.list && test $STYLE/$FAMILY.map -ot $FONT.ps
		then

			# Extract and dump a glyph list from the font for comparison.
			sed -n '/^\/\(..*\) {$/s//\1/p' $FONT.ps | sort -u >$STYLE/$FAMILY.list

			# Filter glyphs that haven't been introduced already and dump a merge map with a proper header.
			printf '%s\n' 'mergeFonts' $(sort -u <<<"$SET" | comm -13 - $STYLE/$FAMILY.list) | sed '2,$s/^.*$/& &/' >$STYLE/$FAMILY.map

		fi

		# Extend the list of glyphs already included with those in the family's map.
		SET=$(echo "$SET"; sed -e '/^mergeFonts$/d' -e '/^#.*$/d' -e 's/^\(..*\) \1$/\1/' $STYLE/$FAMILY.map)

		# Null out the font's encoding to avoid conflicts on merge, and assemble a Type 1 ASCII font file.
		sed '/^dup [0-9][0-9]* \/..* put$/d' $FONT.ps | t1asm -a >$STYLE/$FAMILY.pfa

	done

	# Build an empty Kontrapunkt Pro Type 1 ASCII font file.
	t1asm -a $STYLE/font.ps $STYLE/font.pfa

	# Merge each of the basic families into the Kontrapunkt Pro font file.
	mergeFonts $STYLE/font.pfa $STYLE/font.pfa $(

		# Make a family into the queue only if there's anything in particular to merge.
		# This is necessery, because in case of an empty map the font's whole contents is merged.
		for FAMILY in base ce expert
		do test $(wc -w <$STYLE/$FAMILY.map) -gt 1 && echo $STYLE/$FAMILY.map $STYLE/$FAMILY.pfa
		done

	)


	# POST-PROCESSING

	# Shift glyphs in their em-boxes or change their advance widths if necessary.
	test -f $STYLE/shift.map && rotateFont -t1 -rtf $STYLE/shift.map $STYLE/font.pfa $STYLE/font.pfa

	# Base the PostScript revision number on unique commit count of the source files involved.
	PSREV=$(printf '%03d' $(git rev-list HEAD -- $STYLE/font.ps $CE.ps $EXPERT.ps $STYLE/*.map | wc -l))

	# Make the processing.
	ed -s $STYLE/font.pfa <<<'H
		/^\(%!FontType1-1.1: ..* [0-9]\{3\}\.\)[0-9]\{3\}$/s//\1'$PSREV'/
		/^\(\/version ([0-9]\{3\}\.\)[0-9]\{3\}\()\( readonly\)\{0,1\} def\)$/s//\1'$PSREV'\2/
		wq'


	# OPENTYPE COMPILATION

	# Merge and translate kerning listing from AFM to OpenType syntax.
	sort -u ${BASE}Kern.afm $CE.afm $EXPERT.afm | sed -n 's/^KPX \(.*$\)/pos \1;/p' >$STYLE/features.kern

	# Make the font revision number with appropriate commit count and dump a snippet for inclusion in the features file.
	REV=$(printf '%03d' $(git rev-list HEAD -- FontMenuNameDB GlyphOrderAndAliasDB $STYLE/features features.family $STYLE/fontinfo | wc -l))
	echo "table head { FontRevision 1.$REV; } head;" >$STYLE/fontrev

	# Make the OpenType binaries with all prepared files.
	makeotf -ga -f $STYLE/font.pfa -o build/KontrapunktPro-$STYLE.otf $@

done

exit
