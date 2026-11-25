# Athlos — shortcuts

.PHONY: app run test clean install release

app:            ## Builds build/Athlos.app
	scripts/build_app.sh

run: app        ## Build and open
	open build/Athlos.app

test:           ## Unit tests (AthlosCore)
	scripts/test.sh

install: app    ## Copy to /Applications
	rm -rf /Applications/Athlos.app && cp -R build/Athlos.app /Applications/

release:        ## build/release/Athlos-macOS.dmg + .zip
	scripts/package_release.sh

clean:
	rm -rf .build build
