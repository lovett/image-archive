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

Once installed, run `ia setup` to establish an archive in the default
location, `$HOME/Pictures/Archive`. Run `ia --help setup` for further
details on customizing the name of the archive or its location.

## Configuration

The `config.ini` file defines the "rules" of tagging by mixing
together a couple different concepts.

### Aliases
The `[aliases]` section associates formal tag names with easier
alternatives.

Formal tag names are things like `XMP-photoshop:ColorMode` or
`XMP-xmp:CreateDate`. There are ton of them, and the best resource
for seeing what's available is the [Exiftool website](https://exiftool.org).

A handful of aliases are provided by default but they should be
tailored to your needs. For example, if you're not interested in the
`XMP-xmp:Author` tag, delete that line and then remove any other
references to the word "author" further down in the file.

By itself, an alias is just a shortcut for convenience. The formal tag
is what ultimately gets written to the image.

### Keywords

The majority of `config.ini` is for putting aliases to use by pairing
them with values. In the same way that an alias expands to a formal
tag name, a keyword expands to names and values together.

Some tags are meant to be used with a limited set of values (a
"controlled vocabulary"). Others are more free-form. If you're going
to use the same tag across a number of images, a keyword lets you do
it with one term.

For example, the [XMP-iptcCore:Scene](https://cv.iptc.org/newscodes/scene) tag
uses numeric values to categorize what an image shows. Rather than
remember the number for "A photo taken under water", the
`[underwater]` section associates the word "underwater" with the alias
"scene" and the value "011300". No aquatic images? Delete that section
and the keyword is gone.

Keywords can also expand to multiple tags, as shown in the `[slide]`
section.

### Contexts

The `[contexts]` section determines a minimum set of keywords an image
needs to be tagged with. Like aliases and keywords, the defaults
are just a starting point.

Contexts are about the general case--things you want to account for
the majority of the time, like number of people shown or their
relationship to one another.

During tagging, Image Archive will warn you about unsatisfied contexts
and list the relevant keywords for them. If you're tagging an image
that a context doesn't pertain to such as a landscape photo with no
people in it, prefix the context name with "no" (i.e. "nocount",
"norelationship") and use that as a keyword during tagging.
