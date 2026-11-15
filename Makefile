.PHONY: build test install uninstall run status screenshots clean

build:            ## Compile in release mode
	swift build -c release

test:             ## Run the unit tests
	swift test

install:          ## Build, install, add hooks and start (see scripts/install.sh --help)
	./scripts/install.sh

uninstall:        ## Remove everything (see scripts/uninstall.sh --help)
	./scripts/uninstall.sh

run:              ## Run from the build folder without installing
	swift run -c release ClaudeNotch

status:           ## What is installed, and what the app can see
	swift run -c release ClaudeNotch status

screenshots:      ## Re-render the README screenshots from demo data
	swift run -c release ClaudeNotch render-screenshots docs/images

clean:
	swift package clean
