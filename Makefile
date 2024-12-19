install: uninstall
	zef --to=home install .

uninstall:
	zef uninstall ImageArchive || true

mirror:
	git push --force git@github.com:lovett/image-archive.git master:master
