.PHONY: build test package harness clean
build:
	./scripts/build.sh
test:
	python3 -m unittest discover -s tests -v
package: build
	@test -n "$(IPA)" || (echo 'Use: make package IPA=/absolute/path/to/Spotify.ipa'; exit 1)
	python3 scripts/package_ipa.py --ipa "$(IPA)" --dylib build/Aurora.dylib --output build/Spotify-Aurora-unsigned.ipa
harness:
	./scripts/harness.sh
clean:
	rm -rf build
