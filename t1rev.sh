#!/bin/bash

# Reset the version and/or revision number in a Type 1 font
# Copyright 2013 Grzegorz Rolek


# Subroutine for printing the usage message.
usage () { echo >&2 "usage: $(basename $0) [-v <version>] [-r <revision>] <font>"; exit 2; }

# Parse arguments.
ARGS=$(getopt v:r: $*)

# Make sure no arguments were misused.
test $? != 0 && usage

# Reset the script's arguments.
set -- $ARGS

# Iterate through the arguments.
for ARG
do
	
	# Test and format each of the given numbers.
	# Test if the file argument is present.

	case "$ARG" in

	-v)	VER="$(printf '%03d' $2)"
		shift 2
		test $? != 0 && usage
		;;

	-r)	REV="$(printf '%03d' $2)"
		shift 2
		test $? != 0 && usage
		;;

	--)	FONT="$2"
		test -z $FONT && usage
		break
		;;

	esac

done

# In case both numbers are missing, do nothing.
test -z $VER && test -z $REV && exit

# Reset the numbers.
ed -s $FONT <<<'H
	/^\(%!FontType1..* \)\([0-9]\{1,\}\)\(\.\)\([0-9]\{1,\}\)$/s//\1'${VER="\2"}'\3'${REV="\4"}'/
	/^\(\/version (\)\([0-9]\{1,\}\)\(\.\)\([0-9]\{1,\}\)\()\( readonly\)\{0,1\} def\)$/s//\1'${VER="\2"}'\3'${REV="\4"}'\5/
	wq'

# Done.
exit
