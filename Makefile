install: uninstall
	zef --to=home install .

uninstall:
	zef uninstall ImageArchive || true

setup:
	zef --to=home --deps-only install .

test:
	prove6 --lib t/

mirror:
	git push --force git@github.com:lovett/image-archive.git master:master
