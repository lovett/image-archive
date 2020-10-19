unit module ImageArchive::Config;

use Config::INI;

use ImageArchive::Util;

# List the contexts that have not been explicity disabled by a
# negation keyword.
sub activeContexts(%config, @keywords) is export {
    my @keywordsWithoutNegation = @keywords.map({ $_.subst(/^no/, '')});
    (%config<contexts>.keys (-) @keywordsWithoutNegation).keys;
}

# Determine the set of negation keywords for all known contexts.
# A negation keyword is the name of a context prefixed with "no".
sub contextNegationKeywords(%config) is export {
    %config<contexts>.keys.map({ "no" ~ $_ });
}

# Return the filesystem path of the database.
sub getDatabasePath(%config) is export {
    return %config<_><root>.IO.add("ia.db");
}

# Find all keywords referenced by a context.
#
# A context can consist of aliases or keywords.
sub keywordsInContext(%config, $context) is export {
    my @keywords;

    my @terms = commaSplit(%config<contexts>{$context});

    for %config.kv -> $section, %members {
        next if $section ~~ any <_ aliases prompts contexts>;

        next unless %members.keys (&) @terms or $section ~~ any @terms;
        @keywords.push($section)
    }

    return @keywords;
}

# Gather the tags that correspond to the given keywords.
sub keywordsToTags(%config, @keywords) is export {
    my %tags;

    for %config.kv -> $key, %values {
        %tags.append(%values) if $key ~~ any @keywords;
    }

    return %tags;
}

# Load the application configuration file.
sub readConfig(IO::Path $path = $*HOME.add(".config/ia.conf")) is export {
    my %config;

    return %config unless $path ~~ :f;

    %config = Config::INI::parse(slurp $path);

    unless (%config<_><root>.ends-with('/')) {
        %config<_><root> ~= '/';
    }

    my @skippableSections := <_ aliases prompts contexts>;

    my regex unescape { \\ (<punct>) };

    for %config.kv -> $section, %members {
        next if $section ∈ @skippableSections;

        for %members.kv -> $key, $value {
            # Remove backslash when followed by punctuation.
            %config{$section}{$key} = $value.subst(&unescape, { "$0" }, :g);
        }
    }

    return %config;
}

# Convert an absolute path to a root-relative path.
sub relativePath(%config, Str $file) is export {
    if $file.IO.absolute.starts-with(%config<_><root>) {
        return $file.IO.relative(%config<_><root>);
    }

    return $file;
}


# Map a formal tag back to its corresponding alias.
sub tagToAlias(%config, Str $tag) is export {
    for %config<aliases>.kv -> $alias, $formalTag {
        return $alias if $tag eq $formalTag;
        return $alias if $formalTag.ends-with($tag);
    }

    return $tag;
}

# Create a config file based on a default template.
sub writeStarterConfig(IO::Path $root, IO::Path $configFile = $*HOME.add(".config/ia.conf")) is export {

    if $configFile.f {
        say "The file {$configFile} already exists, so it was left untouched.";
        return;
    }

    spurt $configFile, qq:to/END/;
    ; This is the configuration file for image-archive (ia)
    ; It uses the INI file format.
    ;
    ; After making changes to this file, regenerate the shell completion
    ; file by running: ia-setup completion

    ; Where the images are stored.
    root = {$root.absolute}

    ; The size presets for alternate image generation, specified as
    ; a space-separated list of GraphicsMagic geometry values.
    alt_sizes = 1000x 500x

    ; The file format for alternate image generation.
    alt_format = jpg

    ; The command to run when viewing an image.
    view_command = open -a Preview.app

    ; Questions that should be asked during tagging. They are the opposite
    ; of keywords.
    ;
    ; Use this to gather tag information that varies from file to file.
    ; Keys are aliases and values are the question text.
    [prompts]
    datecreated = Date the picture was taken (YYYY-MM-DD or partial)
    caption     = Caption
    keyword     = Additional keywords
    series      = Series or batch
    seriesid    = ID within series

    ; Aliases for tag names.
    ;
    ; Since tag names are verbose and awkward to type, map them to more friendly
    ; equivalents. Keys are the informal name and values are the formal counterpart.
    [aliases]
    alias       = XMP-photoshop:SupplementalCategories
    author      = XMP-xmp:Author
    caption     = XMP-xmp:Description
    colormode   = XMP-photoshop:ColorMode
    datecreated = XMP-xmp:CreateDate
    datetagged  = XMP-xmp:MetadataDate
    id          = XMP-dc:Identifier
    location    = XMP-iptcExt:LocationCreated
    model       = Model
    object      = ArtworkOrObject
    person      = XMP-iptcExt:PersonInImage
    keyword     = XMP-dc:subject
    scene       = XMP-iptcCore:Scene
    series      = XMP-iptcExt:SeriesName
    seriesid    = XMP-iptcExt:SeriesIdentifier
    sourcetype  = XMP-iptcExt:DigitalSourceType
    subjectcode = XMP-iptcCore:SubjectCode

    ; Filters
    ;
    ; Similar to aliases, this section maps tag names to more friendly
    ; equivalents for narrowing the scope of a search. Keys are the
    ; informal name and values are the formal counterpart without any tag
    ; family prefix.

    [filters]
    alias = SupplementalCategories
    author = Author
    caption = Description
    city = City
    country = CountryName
    created = CreateDate
    event = Event
    keyword = Subject
    location = LocationName
    object = AOContentDescription
    person = PersonInImage
    series = SeriesName
    seriesid = SeriesIdentifier
    source = DigitalSourceType
    state = ProvinceState
    tagged = MetadataDate

    ; Contexts
    ;
    ; A context is a list of comma-separated tag aliases or keywords. They
    ; are a way of enforcing comprehensive tagging by requiring at least one
    ; item from each list to be present.

    [contexts]
    author = author
    count = single, two, group
    location = location
    object = object
    people = person
    relationship = family, marriage, parentchild
    scene = scene
    setting = interiorview, exteriorview
    source = model, sourcetype, colormode

    ; Keywords
    ;
    ; The rest of this file defines tagging keywords. The keyword is the
    ; section name, the keys are aliases, and the values are what will be
    ; ulatimatley be written to the image.
    ;
    ;
    ; Keywords are for applying the same tag value to multiple files, both
    ; for convenience and consistency. They are the opposite of prompts.

    ;; Color mode keywords
    ;; See https://exiftool.org/TagNames/XMP.html#photoshop
    [blackandwhite]
    colormode = Grayscale

    [color]
    colormode = RGB

    ;; Source type keywords
    ;; See http://cv.iptc.org/newscodes/digitalsourcetype/
    [digital]
    sourcetype = digitalCapture

    [negative]
    sourcetype = negativeFilm

    [slide]
    sourcetype = positiveFilm
    keyword = slide

    [photo]
    sourcetype = print

    [software]
    sourcetype = softwareImage

    ;; Scene keywords
    ;; See http://cv.iptc.org/newscodes/scene
    [action]
    scene = 011900

    [aerialview]
    scene = 011200

    [closeup]
    scene = 011800

    [couple]
    scene = 010700

    [exteriorview]
    scene = 011600

    [fulllength]
    scene = 010300

    [generalview]
    scene = 011000

    [group]
    scene = 010900

    [halflength]
    scene = 010200

    [headshot]
    scene = 010100

    [interiorview]
    scene = 011700

    [nightscene]
    scene = 011400

    [offbeat]
    scene = 012300

    [panoramicview]
    scene = 011100

    [performing]
    scene = 012000

    [posing]
    scene = 012100

    [profile]
    scene = 010400

    [rearview]
    scene = 010500

    [satellite]
    scene = 011500

    [single]
    scene = 010600

    [symbolic]
    scene = 012200

    [two]
    scene = 010800

    [underwater]
    scene = 011300

    ; ---- End of the default keyword set ----

    END

    say "Default configuration written to {$configFile}";
    say "Using {$root.absolute} as the archive root.";
}
