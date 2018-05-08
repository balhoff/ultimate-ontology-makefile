ONT=foo
OBO=http://purl.obolibrary.org/obo
DATE=$(shell date +'%Y-%m-%d')
PREFIX=$(OBO)/$(ONT)
RELEASEPREFIX=$(PREFIX)/releases/$(DATE)
ONT_DIR=src/ontology
UTIL=src/util
IMS=target/intermediates
MIRROR=target/mirror
PRODUCTS=target/products

ROBOT_ENV = ROBOT_JAVA_ARGS=-Xmx12G
ROBOT= $(ROBOT_ENV) robot

all: $(PRODUCTS)/$(ONT).owl $(PRODUCTS)/$(ONT)/atomic/$(ONT).owl

$(PRODUCTS)/$(ONT).owl: $(IMS)/$(ONT)-merged.ofn target/$(ONT)-edit-imports.ofn
	# robot merge will automatically remove imports
	$(ROBOT) merge -i $< reason reduce annotate --ontology-iri $(PREFIX)/$(ONT).owl --version-iri $(RELEASEPREFIX)/$(ONT).owl -o $@

$(PRODUCTS)/$(ONT)/atomic/$(ONT).owl: $(IMS)/$(ONT)-merged.ofn
	# Need robot to remove imports
	mkdir -p $(PRODUCTS)/$(ONT)/atomic &&\
	$(ROBOT) annotate -i $< --ontology-iri $(PREFIX)/atomic/$(ONT).owl --version-iri $(RELEASEPREFIX)/atomic/$(ONT).owl -o $@

$(IMS)/$(ONT)-merged.ofn: $(ONT_DIR)/$(ONT)-edit.ofn target/$(ONT)-edit-imports.ofn target/patterns.ofn
	# Need robot to not merge imports
	$(ROBOT) merge -i $(ONT_DIR)/$(ONT)-edit.ofn -i target/patterns.ofn -o $@

pattern_modules := $(patsubst %.yaml, $(IMS)/patterns/%.ofn, $(notdir $(wildcard src/patterns/*.yaml)))

pattern_term_lists := $(patsubst %.yaml, $(IMS)/patterns/%.txt, $(notdir $(wildcard src/patterns/*.yaml)))

$(IMS)/patterns/%.ofn: src/patterns/%.yaml src/patterns/%.tsv target/$(ONT)-edit-imports.ofn $(ONT_DIR)/$(ONT)-edit.ofn
	mkdir -p $(IMS)/patterns &&\
	dosdp-tools generate --catalog=$(UTIL)/catalog-v001-patterngen.xml --infile=$(word 2, $^) --template=$< --ontology=$(ONT_DIR)/$(ONT)-edit.ofn --obo-prefixes=true --outfile=$@

target/patterns.ofn: $(pattern_modules)
	$(ROBOT) merge $(addprefix -i , $(pattern_modules)) annotate --ontology-iri $(PREFIX)/$(ONT)-patterns.ofn -o $@

$(IMS)/patterns/%.txt: src/patterns/%.yaml src/patterns/%.tsv
	mkdir -p $(IMS)/patterns &&\
	dosdp-tools terms --infile=$(word 2, $^) --template=$< --obo-prefixes=true --outfile=$@

$(IMS)/all_pattern_terms.txt: $(pattern_term_lists)
	cat $^ | sort | uniq >$@

target/$(ONT)-edit-imports.ofn: $(ONT_DIR)/$(ONT)-edit-imports.ofn target/terms.txt $(MIRROR)
	ln -f $(ONT_DIR)/$(ONT)-edit-imports.ofn $(MIRROR)/$(ONT)-edit-imports.ofn &&\
	$(ROBOT) extract --method BOT -i $(MIRROR)/$(ONT)-edit-imports.ofn --term-file target/terms.txt -o $@

$(MIRROR): $(ONT_DIR)/$(ONT)-edit-imports.ofn
	rm -rf $@ &&\
	$(ROBOT) mirror -i $< -d target/mirror -o target/mirror/catalog-v001.xml

target/terms.txt: $(ONT_DIR)/$(ONT)-edit.ofn $(ONT_DIR)/import-requests.txt $(IMS)/all_pattern_terms.txt
	# The links are needed because robot doesn't allow direct specification of a catalog file.
	# The "empty" files are needed because we need to query terms from the ontology without trying
	# to load imports, which haven't been created yet--don't use $(IMS)/$(ONT)-merged.ofn here.
	mkdir -p $(IMS) &&\
	ln -f $< $(IMS)/$(ONT)-edit.ofn &&\
	ln -f $(UTIL)/empty.ofn $(IMS)/empty.ofn  &&\
	ln -f $(UTIL)/catalog-v001.xml.empty $(IMS)/catalog-v001.xml &&\
	$(ROBOT) query -i $(IMS)/$(ONT)-edit.ofn -f csv --select src/sparql/terms.sparql $(IMS)/edit-terms.txt &&\
	cat $(IMS)/edit-terms.txt $(ONT_DIR)/import-requests.txt $(IMS)/all_pattern_terms.txt | sort | uniq >$@

clean:
	rm -rf target
