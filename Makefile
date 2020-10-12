# Install the application.
install:
	cp ia ia-setup ~/.local/bin/

# Push the repository to GitHub.
mirror:
	git push --force git@github.com:lovett/image-archive.git master:master

# Install third-party libraries.
setup:
	zef install Config::INI DBIish Terminal::ANSIColor

# Reverse the installation target.
uninstall:
	rm -f ~/.local/bin/ia ~/.local/bin/ia-setup
