unit module ImageArchive::Config;

use experimental :cached;

use Config::INI;

use ImageArchive::Util;

our %config;

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

        when 'cache' {
            return getPath('root').add('_cache');
        }

        when 'html' {
            return getPath('cache').add('html');
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

sub getKeywords() is export {
    my @exclusions = <_ aliases contexts filters prompts>;
    return configSections().grep({ not @exclusions.first($_) });
}

# Find all keywords referenced by a context.
#
# A context can consist of aliases or keywords.
sub keywordsInContext($context) is export {
    my %contexts = readConfig('contexts');
    my @keywords;

    my @terms = commaSplit(%contexts{$context});

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
sub readConfig(Str $lookup?) is export {

    unless (%config) {
        my $target = getPath('config');
        %config = Config::INI::parse_file($target.Str);

        # Remove backslash when followed by punctuation.
        #
        # This is just an editing convenience. The backslashes prevent
        # INI syntax highlighting from getting thrown off.
        my regex unescape { \\ (<punct>) };

        for %config.kv -> $section, %members {
            for %members.kv -> $key, $value {
                %config{$section}{$key} = $value.subst(&unescape, { "$0" }, :g);
            }
        }
    }

    if ($lookup) {
        return %config<_>{$lookup} || %config{$lookup};
    }

    return %config;
}

# List the sections of the config.
sub configSections() is export {
    return readConfig().keys.sort;
}

# Convert an absolute path to a root-relative path.
multi sub relativePath(Str $file) is export {
    my $root = getPath('root');
    if $file.IO.absolute.starts-with($root) {
        return $file.IO.relative($root);
    }

    return $file;
}

# Convert an absolute path to a root-relative path.
multi sub relativePath(IO::Path $file) is export {
    my $root = getPath('root');
    if $file.absolute.starts-with($root) {
        return $file.relative($root);
    }

    return $file;
}

# Create the file that defines application-wide settings.
sub writeApplicationConfig(IO::Path $root) is export {
    my $target = getPath('appconfig');

    return if $target ~~ :f;

    unless ($target.IO.parent.d) {
        mkdir($target.IO.parent);
    }

    spurt $target, qq:to/END/;
    ; This is the application configuration for Image Archive (ia),
    ; defining global settings.
    ;
    ; For archive-specific settings, see the file conf.ini in the archive
    ; root.

    ; The location of the archive as an absolute path.
    root = {$root.absolute}

    END

    say "Wrote {$target}";
}

# Create the file that defines archive-specific settings.
sub writeArchiveConfig() is export {
    my $target = getPath('config');

    my $templatePath = %?RESOURCES<config.ini>.absolute;

    return if $target ~~ :f;

    copy($templatePath, $target.absolute);

    say "Wrote {$target.absolute}";
}
