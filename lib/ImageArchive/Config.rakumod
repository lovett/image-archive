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
