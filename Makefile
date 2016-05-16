# OBI-HOWL Makefile
# James A. Overton <james@overton.ca>
# 2016-05-05
#
# This file defines tasks for converting OBI from OWL format to HOWL format,
# then converting the HOWL back to OWL.


### Configuration
#
# These are standard options to make Make sane:
# <http://clarkgrubb.com/makefile-style-guide#toc2>

MAKEFLAGS += --warn-undefined-variables
SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := all
#.DELETE_ON_ERROR:
.SUFFIXES:
.SECONDARY:

OBI_VERSION := 2015-12-07
OBI_VERSION_IRI := http://purl.obolibrary.org/obo/obi/$(OBI_VERSION)/obi.owl
APACHE_MIRROR := http://www.us.apache.org/dist
SPARQL_URL := http://localhost:3030/db

# Use awk with tabs.
AWK := awk -F "	" -v "OFS=	"

# Old OBI
#
# Fetch selected OBI files from SourceForge Subversion.

svn:
	mkdir -p $@

svn/import:
	mkdir -p $@

.PHONY: fetch-svn
fetch-svn: | svn svn/import
	svn checkout --depth=empty svn://svn.code.sf.net/p/obi/code/trunk/src/ontology/branches/ svn
	svn update svn/obi.owl
	svn update svn/catalog-v001.xml
	svn update svn/doap.template
	svn update svn/external-byhand.owl
	svn update --depth=infinity svn/OntoFox_inputs
	svn update --depth=infinity svn/OntoFox_outputs
	svn update --depth=infinity svn/templates
	svn update --depth=infinity svn/modules
	cp svn/OntoFox_outputs/*.owl svn/import/

# Fetch a recent OBI release.

svn/obi-$(OBI_VERSION).owl: | svn
	curl -Lo $@ $(OBI_VERSION_IRI)


#### Apache Jena
#
# Download and extract.

lib/jena.zip: | lib
	curl -Lo $@ $(APACHE_MIRROR)/jena/binaries/apache-jena-3.0.1.zip

lib/jena: lib/jena.zip
	rm -rf $@
	unzip -q -d lib $<
	mv lib/apache-jena-3.0.1 $@

lib/jena/bin/tdbloader: | lib/jena


#### Apache Jena Fuseki
#
# Download, extract, and configure.

lib:
	mkdir -p $@

lib/fuseki.zip: | lib
	curl -Lo $@ $(APACHE_MIRROR)/jena/binaries/apache-jena-fuseki-2.3.1.zip

lib/fuseki: lib/fuseki.zip
	rm -rf $@
	unzip -q -d lib $<
	mv lib/apache-jena-fuseki-2.3.1 $@

lib/fuseki/tdb: | lib/fuseki
	mkdir -p $@

lib/fuseki/shiro.ini: | lib/fuseki
	echo '[urls]' > $@
	echo '# Everything open' >> $@
	echo '/**=anon' >> $@


### Local Triplestore
#
# Run Fuseki locally from a second shell:
#
#     make fuseki-obi
#     make fuseki

.PHONY: fuseki-obi
fuseki-obi: svn/obi-$(OBI_VERSION).owl | lib/jena/bin/tdbloader lib/fuseki
	$(word 1,$|) --loc $(word 2,$|)/tdb $<

# Run Fuseki in a second shell!
.PHONY: fuseki
fuseki: | lib/fuseki/tdb lib/fuseki/shiro.ini
	cd lib/fuseki && export FUSEKI_HOME=. && ./fuseki-server --loc tdb /db



### Convert OWL to HOWL

define SPARQL_QUERY
curl --fail --silent \
-X POST -G '$(SPARQL_URL)/query' \
-H 'Content-Type: application/sparql-query' \
-H 'Accept: text/tab-separated-values' \
-T
endef

define CLEAN_SPARQL_OUTPUT
| tail -n+2 \
| sed '1s/?//g' \
| sed 's/^"//g' \
| sed 's/"$$//g' \
| sed 's/	"/	/g' \
| sed 's/"	/	/g' \
| sed 's/"^^/^^/g' \
| sed 's/"@en/@en/g'
endef

define REPLACE_PREFIXES
| sed 's!<http://www.w3.org/1999/02/22-rdf-syntax-ns#\([^>]*\)>!rdf:\1!g' \
| sed 's!<http://www.w3.org/2000/01/rdf-schema#\([^>]*\)>!rdfs:\1!g' \
| sed 's!<http://www.w3.org/2001/XMLSchema#\([^>]*\)>!xsd:\1!g' \
| sed 's!<http://www.w3.org/2002/07/owl#\([^>]*\)>!owl:\1!g' \
| sed 's!<http://purl.obolibrary.org/obo/\([A-Za-z]*\)_\([0-9]*\)>!\1:\2!g' \
| sed 's!<http://purl.org/dc/elements/1.1/\([^>]*\)>!dc:\1!g' \
| sed 's!<http://protege.stanford.edu/plugins/owl/protege#\([^>]*\)>!protege:\1!g'
endef

define REPLACE_TYPES
| sed 's/rdf:type: /rdf:type:> /' \
| sed 's/owl:versionIRI: /owl:versionIRI:> /' \
| sed 's/: \(<[^>]*>\)/:> \1/'
endef

ontology/terms.tsv: src/terms.rq
	$(SPARQL_QUERY) $< \
	$(CLEAN_SPARQL_OUTPUT) \
	$(REPLACE_PREFIXES) \
	| sort -u \
	| (echo 'SUBJECT	label:	type:>'; cat -) \
	> $@

ontology/metadata.howl: src/metadata.rq
	echo "obo:obi.owl" > $@
	$(SPARQL_QUERY) $< \
	$(CLEAN_SPARQL_OUTPUT) \
	$(REPLACE_PREFIXES) \
	| sort -u \
	| sed 's/	/: /g' \
	$(REPLACE_TYPES) \
	>> $@


### Convert Imports

import:
	mkdir -p $@

svn/import/BFO_classes_only.owl: | import
	curl -Lo $@ http://purl.obolibrary.org/obo/bfo/2014-05-03/classes-only.owl

svn/import/RO_core.owl: | import
	curl -Lo $@ http://purl.obolibrary.org/obo/ro/releases/2015-10-07/core.owl

svn/import/IAO.owl: | import
	curl -Lo $@ http://purl.obolibrary.org/obo/iao/2015-02-23/iao.owl

import/%.howl: svn/import/%.owl
	java -jar lib/howl.jar \
	--context ontology/prefixes.howl \
	--context ontology/labels.howl \
	--context build/terms.howl \
	--output howl \
	$< > $@

build/%.nt: import/%.howl | build
	java -jar lib/howl.jar \
	--context ontology/prefixes.howl \
	--context ontology/labels.howl \
	--context build/terms.howl \
	--output ntriples \
	$< > $@

build/%.diff: svn/import/%.owl build/%.owl
	robot diff \
	--left svn/import/$*.owl \
	--right build/$*.owl \
	--output $@


### Convert Templates

OBSOLETE_HEADER := SUBJECT	definition:	definition source:	example of usage:	term editor:	alternative term:	IEDB alternative term:	has curation status:	subclass of:>	deprecated: %^^xsd:boolean	has obsolescence reason:>	term replaced by:>

ontology/obsolete.tsv: svn/templates/obsolete.tsv
	< $< \
	tail -n+3 \
	| cut -f2- \
	| (echo "$(OBSOLETE_HEADER)"; cat -) \
	> $@

MIDLEVEL_ASSAYS_HEADER := SUBJECT	definition:	definition source:	example of usage:	term editor:	editor note:	alternative term:	CLASS_TYPE		:>> %	:>> has_specified_output some ('is about' some %)	:>> 'has part' some %	:>> 'has part' some %	:>> (has_specified_input some %) and (realizes some ('evaluant role' and ('inheres in' some %)))	:>> (has_specified_input some %) and (realizes some ('analyte role' and ('inheres in' some %)))	:>> (has_specified_input some %) and (realizes some (function and ('inheres in' some %)))	:>> has_specified_input some %	:>> (has_specified_input some %) and (realizes some ('reagent role' and ('inheres in' some %)))	:>> (has_specified_input some %) and (realizes some ('molecular label role' and ('inheres in' some %)))	:>> has_specified_output some %

ontology/midlevel-assays.tsv: svn/templates/midlevel-assays.tsv
	< $< \
	tail -n+4 \
	| cut -f2- \
	| sed 's/	equivalent	/	equivalent to	/' \
	| sed 's/	subclass	/	subclass of	/' \
	| (echo "$(MIDLEVEL_ASSAYS_HEADER)"; cat -) \
	> $@

EPITOPE_ASSAYS_HEADER := SUBJECT	IEDB alternative term:	definition:	CLASS_TYPE	:>> %	:>> 'has part' some %	:>> has_specified_input some %	:>> (has_specified_input some %) and (realizes some ('reagent role' and ('inheres in' some %)))	:>> has_specified_input some (% and ('has part' some 'MH:>> protein complex'))	:>> has_specified_output some ('information content entity' and ('is about' some %))	:>> has_specified_output some ('information content entity' and ('is about' some (% and ('process is result of' some 'immunoglobulin binding to epitope'))))	:>> has_specified_output some ('information content entity' and ('is about' some (% and ('process is result of' some 'MHC:epitope complex binding to TCR'))))	:>> has_specified_output some %	:>> has_specified_output some ('has measurement unit label' value %)	term editor:	definition source:

ontology/epitope-assays.tsv: svn/templates/epitope-assays.tsv
	< $< \
	tail -n+3 \
	| cut -f2- \
	| $(AWK) '{a=$$2; $$2=$$1; $$1=a; print $$0}' \
	| sed 's/	equivalent	/	equivalent to	/' \
	| sed 's/	subclass	/	subclass of	/' \
	| (echo "$(EPITOPE_ASSAYS_HEADER)"; cat -) \
	> $@


### Convert OBI

# Remove some unnecessary declarations (without any content)
build/obi-clean.owl: svn/obi.owl
	< $< \
	sed '/<owl:Class .*\/>/d' \
	| sed '/<owl:AnnotationProperty .*\/>/d' \
	| sed '/<owl:ObjectProperty .*\/>/d' \
	| sed '/<owl:NamedIndividual .*\/>/d' \
	| sed '/<owl:Datatype .*\/>/d' \
	> $@

ontology/obi.howl: build/obi-clean.owl
	java -jar lib/howl.jar \
	--context ontology/prefixes.howl \
	--context ontology/labels.howl \
	--context build/terms.howl \
	--output howl \
	$< > $@

### Build HOWL

build:
	mkdir -p $@

build/obi.howl: ontology/prefixes.howl ontology/labels.howl build/metadata.howl build/terms.howl import/BFO_classes_only.howl import/RO_core.howl import/IAO.howl import/ChEBI_imports.howl import/GO_imports.howl import/NCBITaxon_imports.howl import/OBO_imports.howl import/PATO_imports.howl import/SO_imports.howl import/UO_imports.howl import/UO_instance_imports.howl build/midlevel-assays.howl build/epitope-assays.howl build/obsolete.howl
	cat $^ > $@

build/metadata.howl: ontology/metadata.howl | build
	< $< \
	sed 's!^owl:versionIRI:> .*!owl:versionIRI:> <$(OBI_VERSION_IRI)>!' \
	> $@

build/%.howl: src/template.py ontology/%.tsv | build
	$^ > $@


### Convert OWL to HOWL

build/%.nt: lib/howl.jar build/%.howl | build
	java -jar $^ > $@

build/%.ttl: build/%.nt
	rapper --input ntriples \
	--output turtle \
	-f 'xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"' \
	-f 'xmlns:rdfs="http://www.w3.org/2000/01/rdf-schema#"' \
	-f 'xmlns:xsd="http://www.w4.org/2001/XMLSchema#"' \
	-f 'xmlns:owl="http://www.w3.org/2002/07/owl#"' \
	-f 'xmlns:obo="http://purl.obolibrary.org/obo/"' \
	$< > $@

build/%.owl: build/%.ttl
	robot convert --input $< --output $@

obi.owl: build/obi.owl
	cp $< $@


### Common Tasks

.PHONY: all
all: obi.owl

.PHONY: tidy
tidy:
	rm -rf build ontology/terms.tsv ontology/metadata.howl ontology/obsolete.tsv

.PHONY: clean
clean: tidy
	rm -rf svn build


