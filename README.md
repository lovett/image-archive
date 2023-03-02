# Image Archive

A command-line tool for adding EXIF tags to image files.

Its main use-case is organizing scanned versions of photographs,
slides, or other printed media. The idea is to build out sets of tag
abbreviations that can be applied to many files like keywords. Once
tagged, the images are organized into date-based subfolders.

# Installation and Setup

Image Archive is written in [Raku](https://raku.org). A working Raku
installation is needed. Other dependencies include
[exiftool](https://exiftool.org) for the writing of the EXIF tags,
[ImageMagick](https://imagemagick.org/index.php) for creating
thumbnails, and [SQLite](https://sqlite.org/index.html) for storing
tag values in a local database that can be searched. Header files for
SQLite are also needed for building a custom extension used for color
arithmetic.

On Fedora, that all boils down to:

```
sudo dnf install sqlite-devel perl-Image-ExifTool ImageMagick
```

Running `make install` from a checkout of this repository will take
care of installing third-party libraries and put the `ia` executable
onto the Raku PATH, usually `$HOME/.raku/bin`.

Once installed, run `ia setup` to establish an archive in the current
directory. A starter configuration file (`config.ini`) will be placed
here along with an empty SQLite database. Run `ia --help setup` for
further details.
