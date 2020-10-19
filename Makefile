# Install the application.
install:
	zef --force-install install .

# Push the repository to GitHub.
mirror:
	git push --force git@github.com:lovett/image-archive.git master:master

# Reverse the installation target.
uninstall:
	zef uninstall ImageArchive
