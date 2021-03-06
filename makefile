# Makefile for Kontrapunkt Pro project directory
# Copyright 2012 Grzegorz Rolek
#
# Use MAKEOTF_OPTIONS to pass custom options into 'makeotf' compiler.


STYLES = Light LightItalic Bold

# Short style names according to the "5:3:3" rule.
STYS = $(foreach STYLE,$(STYLES),$(shell sed 's/\([A-Z][a-z]\{0,2\}\)[a-z]*/\1/g' <<<$(STYLE)))

# Kontrapunkt Pro OpenType binaries.
OTF = $(foreach STYLE,$(STYLES),build/KontrapunktPro-$(STYLE).otf)

# Paths to Kontrapunkt Pro Type 1 families minus the suffixes.
PRO = $(addsuffix /font,$(STYLES))

# Paths to basic families prepared for merging minus the suffixes.
MERGE = $(foreach STYLE,$(STYLES),$(STYLE)/base $(STYLE)/ce $(STYLE)/expert)

# Paths to base Kontrapunkt and derived families minus the various suffixes.
EXPERT = $(addprefix KontrapunktExpert/,$(join $(STYLES),$(foreach STY,$(STYS),/KontrExp$(STY))))
CE = $(addprefix KontrapunktCE/,$(join $(STYLES),$(foreach STY,$(STYS),/KontrCE$(STY))))
BASE = $(subst CE,,$(CE))

# Normally, in static pattern rules with a filter function, it's the filter who interprets the % wildcard.
# Secondary expansion makes things tricky, though, and it seems that's no longer the case.
# The variable below escaped twice makes sure the % wildcard indeed goes into the filter itself.
WLDCRD = %


# KONTRAPUNKT PRO OPENTYPE BINARIES

# There's apparently no kerning listing in the original ASCII metrics, nor in the FOND resources,
# but still, there's one in the printer binaries, so it's taken out and written into a new ASCII metrics file.
# Feeding the kerndump.sh with encoding the binaries were probably generated with originally.
# The font revision number (based on appropriate commit count) goes with a snippet included in the feature file.

all: $(OTF)

$(OTF): build/KontrapunktPro-%.otf: %/font.pfa %/features features.family FontMenuNameDB GlyphOrderAndAliasDB %/fontinfo | \
	%/features.kern %/fontrev build
	makeotf -ga -f $< -o $@ $(MAKEOTF_OPTIONS)

$(addsuffix /fontrev,$(STYLES)): %/fontrev: FontMenuNameDB GlyphOrderAndAliasDB %/features features.family %/fontinfo
	REV=$$(printf '%03d' $$(git rev-list HEAD -- \
		FontMenuNameDB GlyphOrderAndAliasDB $*/features features.family $*/fontinfo | wc -l)); \
	echo "table head { FontRevision 1.$$REV; } head;" >$@

.SECONDEXPANSION:
$(addsuffix /features.kern,$(STYLES)): %/features.kern: $$(filter Kontrapunkt/$$*/$$(WLDCRD),$$(BASE))Kern.afm
	sort -u $< $(filter KontrapunktCE/$*/%,$(CE)).afm $(filter KontrapunktExpert/$*/%,$(EXPERT)).afm | \
	sed -n 's/^KPX \(.*$$\)/pos \1;/p' >$@

$(addsuffix Kern.afm,$(BASE)): %Kern.afm: %.pfm default.enc %.afm
	LC_CTYPE=C; tr '\r' '\n' <$*.afm >$@
	printf '%s\n' /EndCharMetrics/+1i "$$(sh kerndump.sh -e default.enc $*.pfm)" . wq | ed -s $@

build:
	mkdir build


# KONTRAPUNKT PRO TYPE 1 FAMILY

# The encodings of all three basic families are nulled out to avoid conflicts on merge.
# Pre-prepared merge maps exclude some glyphs of the original family,
# letting the duplicate glyphs in derived families to be merged in instead.
# PostScript revision number is reset with unique commit count of the source files involved.

pro: $(addsuffix .pfa,$(PRO))

.SECONDEXPANSION:
.ONESHELL:
$(addsuffix .pfa,$(PRO)): %/font.pfa: %/font.ps $$(wildcard $$*/base.map) $$(wildcard $$*/ce.map) $$(wildcard $$*/expert.map) \
	$$(addsuffix .pfa,$$*/base $$*/ce $$*/expert) $$(wildcard $$*/shift.map)
	t1asm -a $*/font.ps $@
	bash t1merge.sh $@ $@ $*/base.pfa $*/ce.pfa $*/expert.pfa
	-test -f $*/shift.map && rotateFont -t1 -rtf $*/shift.map $@ $@
	sh t1rev.sh -r $$(git rev-list HEAD -- \
		$*/font.ps $(filter KontrapunktCE/$*/%,$(CE)).ps $(filter KontrapunktExpert/$*/%,$(EXPERT)).ps $*/*.map | wc -l) $@

.SECONDEXPANSION:
$(addsuffix .pfa,$(filter %expert,$(MERGE))): %/expert.pfa: $$(filter KontrapunktExpert/$$*/$$(WLDCRD),$$(EXPERT)).ps
	sed '/^dup [0-9][0-9]* \/..* put$$/d' $< | t1asm -a >$@

.SECONDEXPANSION:
$(addsuffix .pfa,$(filter %ce,$(MERGE))): %/ce.pfa: $$(filter KontrapunktCE/$$*/$$(WLDCRD),$$(CE)).ps
	sed '/^dup [0-9][0-9]* \/..* put$$/d' $< | t1asm -a >$@

.SECONDEXPANSION:
$(addsuffix .pfa,$(filter %base,$(MERGE))): %/base.pfa: $$(filter Kontrapunkt/$$*/$$(WLDCRD),$$(BASE)).ps
	sed '/^dup [0-9][0-9]* \/..* put$$/d' $< | t1asm -a >$@

$(addsuffix .ps,$(BASE)): %.ps: %
	macbinary encode -p $< | t1unmac -a | t1disasm >$@


# BASE KONTRAPUNKT TYPE 1 FAMILY & DERIVATIVES

# Mac-specific Type 1 fonts store font programs in POST resource forks;
# they were archived with resource-savvy 'ditto' utility for repository storage.

base: $(addsuffix .pfa,$(BASE))
ce: $(addsuffix .pfa,$(CE))
expert: $(addsuffix .pfa,$(EXPERT))

$(addsuffix .pfa,$(CE) $(EXPERT)): %.pfa: %.ps
	t1asm -a $< $@

$(addsuffix .pfa,$(BASE)): %.pfa: %
	macbinary encode -p $< | t1unmac -a >$@

# This rule extracts files from archive with file modification dates older then the archive itself.
# It would trigger the recipe each and every time, unless the order-only prerequisite is used.
$(BASE): %: | %.cpgz
	ditto -x $| $(dir $@)


# TESTING & CLEANING

test: $(OTF)
	@cd build; compareFamily; cd ..

lint: $(addsuffix .pfa,$(CE) $(EXPERT) $(PRO))
	-@t1lint $(addsuffix .pfa,$(CE) $(EXPERT) $(PRO))

check: $(addsuffix .pfa,$(CE) $(EXPERT))
	@rm -f $(addsuffix .log,$(CE) $(EXPERT))
	-@for FONT in $(CE) $(EXPERT); do \
	echo $$FONT.pfa; \
	checkOutlines -i -log $$FONT.log $$FONT.pfa | grep 'Warning:'; \
	done

cleanall: clean
	@rm -fr build

clean:
	@rm -fr $(BASE) $(addsuffix .ps,$(BASE)) \
		$(addsuffix .pfa,$(BASE) $(CE) $(EXPERT) $(PRO)) \
		$(addsuffix .pfa,$(MERGE)) $(filter-out Light/base.map Bold/base.map,$(addsuffix .map,$(MERGE))) \
		$(addsuffix Kern.afm,$(BASE)) $(addsuffix /features.kern,$(STYLES)) \
		$(addsuffix /fontrev,$(STYLES)) \
		$(addsuffix /current.fpr,$(STYLES)) \
		$(addsuffix .log,$(CE) $(EXPERT))
