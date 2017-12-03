BUILD_DIR=build
RELEASE_DIR=release
PACKAGE_DIR=out
HTML_FILE=$(BUILD_DIR)/index.html
JS_FILE=$(BUILD_DIR)/elm.js
ASSETS_PATH = $(BUILD_DIR)/assets

JS_SOURCES = $(wildcard src/*.elm src/*/*.elm)
ASSET_FILES = $(shell find assets -type f)
MAIN_FILE = $(BUILD_DIR)/main.js
CSS_FILES = $(wildcard static/*.scss)
CSS_TARGETS = $(subst static,build,$(CSS_FILES:.scss=.css))

ELECTRON_PACKAGER=./node_modules/electron-packager/cli.js

SASS_CMD=./node_modules/node-sass/bin/node-sass

all: $(BUILD_DIR) static $(JS_FILE)

run: all
	NODE_ENV=development electron $(MAIN_FILE)

run-prod: all
	NODE_ENV=production electron $(MAIN_FILE)

run-debug: $(BUILD_DIR) static
	elm make src/Main-Debugger.elm --output $(JS_FILE) --debug
	NODE_ENV=development electron $(MAIN_FILE)
	rm $(JS_FILE)

run-watch: all
	$(SASS_CMD) --watch --recursive --output build/ --source-map true --source-map-contents static/ &
	NODE_ENV=development electron $(MAIN_FILE) &
	npm run watch

watch-css: all
	$(SASS_CMD) --watch --recursive --output build/ --source-map true --source-map-contents static/

package-setup: all
	cp icon.* $(BUILD_DIR)
	cp package.json $(BUILD_DIR)
	sed -i -e "s/build\/main/main/g" $(BUILD_DIR)/package.json
	cd $(BUILD_DIR) && npm install --production

release-setup: all
	rm -rf $(RELEASE_DIR)/tmp/*
	mkdir -p $(RELEASE_DIR)/tmp/syncrypt
	mkdir -p $(RELEASE_DIR)/tmp/build
	cp icon.* $(RELEASE_DIR)/tmp/
	cp -r $(BUILD_DIR)/* $(RELEASE_DIR)/tmp/syncrypt
	cp package.json $(RELEASE_DIR)/tmp/
	sed -i -e "s/build\/main/syncrypt\/main/g" $(RELEASE_DIR)/tmp/package.json
	sed -i -e "s/\"electron-forge\": \"^4.0.2\",//g" $(RELEASE_DIR)/tmp/package.json
	cp client/* $(RELEASE_DIR)/tmp/syncrypt/
	cd $(RELEASE_DIR)/tmp && npm install

release: release-setup
	#cd $(BUILD_DIR) && electron-packager ./ Syncrypt --overwrite
	cd $(RELEASE_DIR)/tmp && \
		npm run make-installer
	mv $(RELEASE_DIR)/tmp/out/make/* $(RELEASE_DIR)/

Syncrypt-Desktop-linux.zip: all
	rm -rf $(PACKAGE_DIR) $@
	$(ELECTRON_PACKAGER) $(BUILD_DIR) --platform linux --out $(PACKAGE_DIR)
	(cd $(PACKAGE_DIR); zip --symlinks -r ../$@ .)

Syncrypt-Desktop-darwin.zip: all
	rm -rf $(PACKAGE_DIR) $@
	$(ELECTRON_PACKAGER) $(BUILD_DIR) --platform darwin --icon=icon.icns --out $(PACKAGE_DIR)
	(cd $(PACKAGE_DIR); zip --symlinks -r ../$@ .)

Syncrypt-Desktop-win32.zip: all
	rm -rf $(PACKAGE_DIR) $@
	$(ELECTRON_PACKAGER) $(BUILD_DIR) --platform win32 --icon=icon.ico --out $(PACKAGE_DIR)
	(cd $(PACKAGE_DIR); zip --symlinks -r ../$@ .)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

static: $(BUILD_DIR)/index.html $(CSS_TARGETS) $(ASSETS_PATH)

$(BUILD_DIR)/index.html : static/main.html static/main.js static/ports.js
	cp static/main.html $(BUILD_DIR)/index.html
	cp static/main.js $(BUILD_DIR)/
	cp static/ports.js $(BUILD_DIR)/

build/%.css: static/%.scss
	$(SASS_CMD) $< $@

$(ASSETS_PATH): $(ASSET_FILES)
	mkdir -p $(ASSETS_PATH)
	cp -r assets/* $(ASSETS_PATH)

$(JS_FILE): $(JS_SOURCES)
	elm make src/Main.elm --output $(BUILD_DIR)/elm.js $(DEBUG)

test-setup:
	cd tests && elm-install

test:
	elm-test

deps:
	npm install && elm-install

clean-deps:
	rm -rf elm-stuff
	rm -rf node_modules/

clean:
	rm -rf $(BUILD_DIR)
	rm -rf $(PACKAGE_DIR)
	rm -rf $(RELEASE_DIR)/tmp/
	rm -rf Syncrypt-Desktop-linux.zip Syncrypt-Desktop-darwin.zip Syncrypt-Desktop-win32.zip

distclean: clean clean-deps
	rm -rf $(RELEASE_DIR)
