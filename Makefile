.PHONY: build install clean

build:
	xcodebuild -project GCalApp.xcodeproj -target GCalApp -configuration Release build SYMROOT=build

install: build
	cp -r build/Release/GCalApp.app /Applications/
	@echo "GCalApp installed to /Applications"

clean:
	rm -rf build
