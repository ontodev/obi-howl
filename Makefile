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
.DELETE_ON_ERROR:
.SUFFIXES:
.SECONDARY:

OBI_VERSION := 2015-12-07
OBI_VERSION_IRI := http://purl.obolibrary.org/obo/obi/$(OBI_VERSION)/obi.owl
APACHE_MIRROR := http://www.us.apache.org/dist
SPARQL_URL := http://localhost:3030/db


# Old OBI
#
# Fetch selected OBI files from SourceForge Subversion.

old:
	mkdir -p $@
	svn checkout --depth=empty svn://svn.code.sf.net/p/obi/code/trunk/src/ontology/branches/ $@
	svn update $@/obi.owl
	svn update $@/catalog-v001.xml
	svn update $@/doap.template
	svn update $@/external-byhand.owl
	svn update --depth=infinity $@/OntoFox_inputs
	svn update --depth=infinity $@/OntoFox_outputs
	svn update --depth=infinity $@/templates
	svn update --depth=infinity $@/modules

# Fetch a recent OBI release.

old/obi-$(OBI_VERSION).owl: | old
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
fuseki-obi: old/obi-$(OBI_VERSION).owl | lib/jena/bin/tdbloader lib/fuseki
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


### Build HOWL

build:
	mkdir -p $@

build/obi.howl: ontology/prefixes.howl ontology/labels.howl build/metadata.howl build/terms.howl
	cat $^ > $@

build/metadata.howl: ontology/metadata.howl | build
	< $< \
	sed 's!^owl:versionIRI:> .*!owl:versionIRI:> <$(OBI_VERSION_IRI)>!' \
	> $@

build/terms.howl: src/template.py ontology/terms.tsv | build
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
	$< > $@

build/%.owl: build/%.ttl
	robot convert --input $< --output $@


### Common Tasks

.PHONY: all
all: build/obi.owl

.PHONY: tidy
tidy:
	rm -rf build ontology/terms.tsv ontology/metadata.howl

.PHONY: clean
clean:
	rm -rf old build


