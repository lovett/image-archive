# Image Archive

A command-line tool for adding EXIF tags to image files.

Its main use-case is organizing scanned versions of photographs,
slides, or other printed media. The idea is to build out sets of tag
abbreviations that can be applied to many files like keywords. Once
tagged, the images are organized into date-based subfolders.

# Setup and Installation

Image Archive is written in [Raku](https://raku.org). A working Raku
installation is needed. Other dependencies include
[exiftool](https://exiftool.org) for the writing of the EXIF tags,
[ImageMagick](https://imagemagick.org/index.php) for creating
thumbnails, and [SQLite](https://sqlite.org/index.html) for storing
tag values in a local database that can be searched.

Running `make install` from a checkout of this repository will take
care of installing third-party libraries and put the `ia` executable
onto the Raku PATH, usually `$HOME/.raku/bin`.

Once installed, run `ia setup <path>` to establish the archive. A
skeleton configuration file (`config.ini`) will be placed here along
with an empty SQLite database.
