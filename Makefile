.PHONY: help all clean build run app install watch gh-pub

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
	@echo "  make gh-pub       - Build release, tag and publish to GitHub"
	@echo "  make help         - Show this help message"
	@echo ""

clean:
	@echo "Cleaning build artifacts..."
	@swift package clean
	@rm -rf .build
	@echo "Clean complete"

build:
	@echo "Building $(APP_NAME)..."
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
	@VERSION=$$(date +%Y.%m.%d-%H%M); \
	echo "Publishing v$$VERSION to GitHub..."; \
	tar -czf $(APP_NAME).app.tar.gz -C /Applications $(APP_NAME).app; \
	git tag -f "v$$VERSION"; \
	git push origin main --tags --force; \
	gh release create "v$$VERSION" $(APP_NAME).app.tar.gz \
		--title "v$$VERSION" \
		--notes "Release v$$VERSION" \
		--latest; \
	rm -f $(APP_NAME).app.tar.gz; \
	echo "Published v$$VERSION"

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
