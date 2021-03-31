# Install the application.
#
# DBIIsh is given special installation treatment to avoid a test suite
# error as of v0.6.2.
install:
	zef install DBIish --force-test
	zef uninstall ImageArchive || true
	zef install .

# Push the repository to GitHub.
mirror:
	git push --force git@github.com:lovett/image-archive.git master:master

# Reverse the installation target.
uninstall:
	zef uninstall ImageArchive
