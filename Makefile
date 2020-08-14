# Install the application.
install:
	cp ia ~/.local/bin/

# Push the repository to GitHub.
mirror:
	git push --force git@github.com:lovett/image-archive.git master:master

# Install third-party libraries.
setup:
	zef install Config::INI DBIish Terminal::ANSIColor
