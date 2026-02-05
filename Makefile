.PHONY: help all clean build run app install watch

default: build run

help:
	@echo "File Explorer Makefile"
	@echo ""
	@echo "Usage:"
	@echo "  make              - Build, install and run the app"
	@echo "  make all          - Same as default"
	@echo "  make build        - Build the app"
	@echo "  make app          - Create .app bundle"
	@echo "  make install      - Install to ~/Applications"
	@echo "  make run          - Run the installed app"
	@echo "  make clean        - Remove build artifacts"
	@echo "  make help         - Show this help message"
	@echo ""

clean:
	@echo "Cleaning build artifacts..."
	@swift package clean
	@rm -rf .build
	@echo "Clean complete"

build:
	@echo "Building FileExplorer..."
	@swift build
	@echo "Creating app bundle..."
	@mkdir -p FileExplorer.app/Contents/MacOS
	@mkdir -p FileExplorer.app/Contents/Resources
	@cp app/Info.plist FileExplorer.app/Contents/
	@cp .build/debug/FileExplorer FileExplorer.app/Contents/MacOS/
	@cp /opt/homebrew/bin/fzf FileExplorer.app/Contents/MacOS/
	@codesign --force --sign - --entitlements FileExplorer.entitlements FileExplorer.app/Contents/MacOS/FileExplorer 2>/dev/null || true
	@pkill -x "FileExplorer" 2>/dev/null || true
	@sleep 0.3
	@rm -rf ~/Applications/FileExplorer.app
	@cp -R FileExplorer.app ~/Applications/
	@rm -rf FileExplorer.app
	@echo "Installed to ~/Applications/FileExplorer.app"

run:
	@echo "Running FileExplorer..."
	@open ~/Applications/FileExplorer.app

watch:
	@echo "Watching for Swift file changes..."
	@touch .watch_timestamp
	@while true; do \
		find app -name "*.swift" -newer .watch_timestamp 2>/dev/null | grep -q . && \
		(echo "Changes detected, rebuilding..." && \
		 pkill -x "File Explorer" 2>/dev/null; \
		 make build \
		 touch .watch_timestamp); \
		sleep 1; \
	done
