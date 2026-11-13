NAME := GCB
URL := https://guyclaude-burger.codeberg.page/
BIBFILE := ../references.bib
CSL := ../biomed-central.csl
ARCHIVE := $(HOME)/Documents/.archives/$(NAME)-HUGO
LUA_FILTER := ./editorial.lua
.ONESHELL:
.DELETE_ON_ERROR:
.DEFAULT_GOAL := preview
.PHONY: preview production archive deploy

notify = notify-send -e -u $(1) "$(NAME): $(2)"

FILES   := $(shell find . -type f -not -path './public/*' -not -path './.git/*' -not -path './resources/*')
SOURCES := Makefile $(filter ./assets/% ./content/% ./layouts/% ./static/% ./data/% ./i18n/% ./themes/googlesite-common/%,$(FILES))
DJ_HTML := $(patsubst %.dj,%.html,$(filter %.dj,$(FILES)))

$(DJ_HTML): %.html: %.dj $(LUA_FILTER)
	n=$$(sed -n '/^---$$/=' $< | sed -n 2p)
	head -n $$n $< > $@
	echo >> $@
	tail -n +$$((n+1)) $< | pandoc -f djot -t tei --wrap=none --lua-filter=$(word 2,$^) >> $@

# Bibliography, in two steps so .DELETE_ON_ERROR cleans up failures
.bibliography.html: $(BIBFILE) $(CSL)
	printf -- '---\nnocite: "@*"\n---\n' \
	| pandoc --citeproc --bibliography=$< --csl=$(word 2,$^) --wrap=none -f markdown -t html > $@

data/bibliography.yaml: .bibliography.html
	mkdir -p $(@D)
	perl -0777 -ne '
		while (/<div id="ref-([^"]+)"[^>]*>(.*?)<\/div>\s*(?=<div id="ref-|\z)/gs) {
			my ($$key,$$html)=($$1,$$2);
			$$html =~ s/<\/?div[^>]*>//g;
			$$html =~ s/^\s+|\s+$$//g;
			$$html =~ s/^\d+\.\s*//;
			print "$$key: |-\n  $$html\n";
		}' $< > $@

public: data/bibliography.yaml $(SOURCES) $(DJ_HTML)
	hugo --minify --cleanDestinationDir -b "$(URL)" 2>/tmp/hugo.log \
		|| { $(call notify,critical,Hugo failed); exit 1; }
	touch $@

preview: data/bibliography.yaml $(SOURCES)
	if lsof -a -iTCP:1313 -c hugo >/dev/null; then
		open http://localhost:1343
	else
		hugo server -M -D --minify --navigateToChanged -O || $(call notify,critical,Hugo FAILED)
	fi

production:
	open "$(URL)"

archive: $(SOURCES) $(DJ_HTML) data/bibliography.yaml
	mkdir -p "$(ARCHIVE)"
	rsync -a --delete --exclude=resources --include='public/' --include='public/.git/**' --exclude='public/*' ./ "$(ARCHIVE)/"
	$(call notify,low,archive created)

# first-time setup: cd public && git init && git remote add origin <remote>
deploy: public
	git -C $< add .
	git -C $< diff --cached --quiet && exit 0
	git -C $< commit -m "update site"
	git -C $< push -f && $(call notify,low,Deploy OK) || { $(call notify,critical,Deploy FAILED); exit 1; }
