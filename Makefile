# Install third-party libraries.
# Anything listed here should also be in ansible/install.yml.
setup:
	sudo zef install Config::INI DBIish Terminal::ANSIColor

# Push the repository to GitHub.
mirror:
	git push --force git@github.com:lovett/image-archive.git master:master
