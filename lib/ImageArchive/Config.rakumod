unit module ImageArchive::Config;

use experimental :cached;

use Config::INI;

use ImageArchive::Util;

# List the contexts that have not been explicity disabled by a
# negation keyword.
sub activeContexts(@keywords) is export {
    my %contexts = readConfig('contexts');
    my @keywordsWithoutNegation = @keywords.map({ $_.subst(/^no/, '')});
    (%contexts.keys (-) @keywordsWithoutNegation).keys;
}

# Determine the set of negation keywords for all known contexts.
# A negation keyword is the name of a context prefixed with "no".
sub contextNegationKeywords(%contexts) is export {
    %contexts.keys.map({ "no" ~ $_ });
}

# Lookup an application file path by keyword.
sub getPath(Str $keyword) is export is cached {
    given $keyword {
        when 'appconfig' {
            return $*HOME.add('.config/ia.conf');
        }

        when 'config' {
            return getPath('root').add('config.ini');
        }

        when 'completion-fish' {
            return $*HOME.add(".config/fish/completions/ia.fish");
        }

        when 'database' {
            return getPath('root').add('ia.db');
        }

        when 'root' {
            my $appConfig = getPath('appconfig');

            my %ini = Config::INI::parse_file($appConfig.Str);

            my $root = %ini<_><root>;
            $root ~= '/' unless $root.ends-with('/');
            return $root.IO;
        }
    }
}

# Find all keywords referenced by a context.
#
# A context can consist of aliases or keywords.
sub keywordsInContext($context) is export {
    my %config = readConfig();
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
sub keywordsToTags(@keywords) is export {
    my %config = readConfig();
    my %tags;

    for %config.kv -> $key, %values {
        %tags.append(%values) if $key ~~ any @keywords;
    }

    return %tags;
}

# Load the application configuration file.
sub readConfig(Str $section?) is export is cached {
    my IO::Path $target = getPath('config');

    my %config;

    return %config unless $target ~~ :f;

    %config = Config::INI::parse(slurp $target);

    my @skippableSections := <_ aliases prompts contexts>;

    my regex unescape { \\ (<punct>) };

    for %config.kv -> $section, %members {
        next if $section ∈ @skippableSections;

        for %members.kv -> $key, $value {
            # Remove backslash when followed by punctuation.
            %config{$section}{$key} = $value.subst(&unescape, { "$0" }, :g);
        }
    }

    if ($section) {
        return %config{$section};
    }

    return %config;
}

# Convert an absolute path to a root-relative path.
sub relativePath(Str $file) is export {
    my $root = getPath('root');
    if $file.IO.absolute.starts-with($root) {
        return $file.IO.relative($root);
    }

    return $file;
}


# Map a formal tag back to its corresponding alias.
sub tagToAlias(Str $tag) is export {
    my %aliases = readConfig('aliases');
    for %aliases.kv -> $alias, $formalTag {
        return $alias if $tag eq $formalTag;
        return $alias if $formalTag.ends-with($tag);
    }

    return $tag;
}

# Create the file that defines the location of the archive.
sub writeApplicationConfig(IO::Path $root) is export {
    my $target = getPath('appconfig');

    return if $target ~~ :f;

    spurt $target, qq:to/END/;
    ; This is the application configuration for image-archive (ia).
    ;
    ; The location of the archive as an absolute path.
    root = {$root.absolute}

    END

    say "Wrote {$target}";
}

# Create the file that defines tag terms and archive-specific settings.
sub writeArchiveConfig() is export {
    my $target = getPath('config');

    my $templatePath = %?RESOURCES<config.ini>.absolute;

    return if $target ~~ :f;

    copy($templatePath, $target.absolute);

    say "Wrote {$target.absolute}";
}
