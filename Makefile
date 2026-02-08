.PHONY: help all clean build run app install watch gh-pub lint test demo

APP_NAME = FileExplorerByDux

default: build run

help:
	@echo "File Explorer Makefile"
	@echo ""
	@echo "Usage:"
	@echo "  make              - Build, install and run the app"
	@echo "  make all          - Same as default"
	@echo "  make build        - Build the app"
	@echo "  make app          - Create .app bundle"
	@echo "  make install      - Install to /Applications"
	@echo "  make run          - Run the installed app"
	@echo "  make clean        - Remove build artifacts"
	@echo "  make lint         - Run SwiftLint"
	@echo "  make test         - Run tests"
	@echo "  make demo         - Start web server and open demo page"
	@echo "  make gh-pub       - Build release, tag and publish to GitHub"
	@echo "  make help         - Show this help message"
	@echo ""

clean:
	@echo "Cleaning build artifacts..."
	@swift package clean
	@rm -rf .build
	@echo "Clean complete"

build: lint
	@echo "Building $(APP_NAME)..."
	@git rev-parse HEAD > app/Resources/build-commit.txt
	@swift build
	@echo "Creating app bundle..."
	@mkdir -p $(APP_NAME).app/Contents/MacOS
	@mkdir -p $(APP_NAME).app/Contents/Resources
	@cp app/Info.plist $(APP_NAME).app/Contents/
	@cp .build/debug/FileExplorer $(APP_NAME).app/Contents/MacOS/FileExplorer
	@cp app/Resources/AppIcon.icns $(APP_NAME).app/Contents/Resources/
	@cp -R .build/debug/FileExplorer_FileExplorer.bundle $(APP_NAME).app/Contents/Resources/
	@cp -R .build/debug/FileExplorer_FileExplorer.bundle $(APP_NAME).app/
	@codesign --force --sign - --entitlements FileExplorer.entitlements $(APP_NAME).app/Contents/MacOS/FileExplorer 2>/dev/null || true
	@pkill -x "FileExplorer" 2>/dev/null || true
	@sleep 0.3
	@rm -rf /Applications/$(APP_NAME).app
	@cp -R $(APP_NAME).app /Applications/
	@rm -rf $(APP_NAME).app
	@echo "Installed to /Applications/$(APP_NAME).app"

run:
	@echo "Running $(APP_NAME)..."
	@open /Applications/$(APP_NAME).app

gh-pub: build
	@HASH=$$(git rev-parse --short HEAD); \
	sed -i '' "s|/main/install.sh.*|/main/install.sh?v=$$HASH \| bash|" README.md; \
	git add -A && git commit -m "release" --allow-empty && git push origin main; \
	echo "Deleting old releases..."; \
	gh release list --json tagName -q '.[].tagName' | while read tag; do \
		gh release delete "$$tag" --yes --cleanup-tag 2>/dev/null; \
	done; \
	echo "Publishing latest release..."; \
	tar -czf $(APP_NAME).app.tar.gz -C /Applications $(APP_NAME).app; \
	gh release create latest $(APP_NAME).app.tar.gz \
		--title "$(APP_NAME)" \
		--notes "Latest build" \
		--latest; \
	rm -f $(APP_NAME).app.tar.gz; \
	echo "Published"

lint:
	@swiftlint lint --quiet

test:
	@swift test

demo:
	@echo "Starting web server for demo..."
	@open http://localhost:8000/web-demo/
	@python3 -m http.server 8000

watch:
	@echo "Watching for Swift file changes..."
	@touch .watch_timestamp
	@while true; do \
		find app -name "*.swift" -newer .watch_timestamp 2>/dev/null | grep -q . && \
		(echo "Changes detected, rebuilding..." && \
		 pkill -x "FileExplorer" 2>/dev/null; \
		 make build \
		 touch .watch_timestamp); \
		sleep 1; \
	done
