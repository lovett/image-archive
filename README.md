# Image Archive

A command-line tool for adding metadata tags to image files.

Its main use-case is organizing scanned versions of photographs,
slides, or other printed media. The idea is to build up a collection
of tags that can be applied to many files with relatively little
effort, but relatively high confidence that the tagging is consistent
and comprehensive.

The tool is invoked on the command line as `ia`. Given an image file
and a series of human-friendly keywords, it will write the
corresponding "formal" tag using [exiftool](https://exiftool.org) and
then relocate the file to a designated location subfoldered by date.

These tagged files can then be searched, again favoring human-readable
syntax. There is also support for creating workspace where a given
file can be edited and versioned.

# Setup and Installation

Image Archive is written in [Raku](https://raku.org). A working Raku
installation is needed. Other dependencies include
[exiftool](https://exiftool.org),
[ImageMagick](https://imagemagick.org/index.php), and
[SQLite](https://sqlite.org/index.html).

Running `make install` from a checkout of this repository will take
care of installing third-party libraries and put the `ia` executable
onto the Raku PATH, usually `$HOME/.raku/bin`.

Once installed, run `ia setup <path>` to establish the archive. A
skeleton configuration file (`config.in`) will be placed here along
with the SQLite database.
