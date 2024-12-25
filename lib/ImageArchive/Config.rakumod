unit module ImageArchive::Config;

use experimental :cached;

use Config::INI;

our %config;

# Determine the set of negation keywords for all known contexts.
# A negation keyword is the name of a context prefixed with "no".
sub contextNegationKeywords(%contexts) is export {
    %contexts.keys.map({ "no" ~ $_ });
}

# Lookup an application file path by keyword.
sub appPath(Str $keyword --> IO::Path) is export is cached {
    given $keyword {
        when 'cache' {
            return appPath('root').add('_cache');
        }

        when 'html' {
            return appPath('cache').add('html');
        }

        when 'config' {
            return appPath('root').add('config.ini');
        }

        when 'completion-fish' {
            return $*HOME.add(".config/fish/completions/ia.fish");
        }

        when 'database' {
            return appPath('root').add('ia.db');
        }

        when 'root' {
            my $root = %*ENV<IA_ROOT> //  "{$*HOME}/Pictures/Archive";
            return $root.IO;
        }
    }
}

sub getKeywords() is export {
    my @exclusions = <_ aliases contexts filters prompts>;
    return configSections().grep({ not @exclusions.first($_) });
}

# Figure out if a word is a keyword or alias.
sub identifyTerm(Str $term) is export returns Str {
    my @keywords = getKeywords();
    return 'keyword' if @keywords.grep($term);

    my @aliases = readConfig('aliases').keys;
    return 'alias' if @aliases.grep($term);

    return '';
}

# Find all keywords referenced by a context.
#
# A context can consist of aliases or keywords.
sub keywordsInContext($context) is export {
    my %contexts = readConfig('contexts');
    my @keywords;

    my @terms = %contexts{$context}.split(",").map(*.trim);

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

sub loadConfig() is export is cached {
    my $path = appPath("config");

    my %config = Config::INI::parse_file($path.Str);

    my regex unescape { \\ (<punct>) };

    for %config.kv -> $section, %members {
        for %members.kv -> $key, $value {
            %config{$section}{$key} = $value.subst(&unescape, { "$0" }, :g);
        }
    }

    return %config;
}

#| Load the config file for the active repository.
sub readConfig(Str $lookup?) is export {
    my %config = loadConfig();

    if ($lookup) {
        return %config<_>{$lookup} || %config{$lookup};
    }

    return %config;
}


# List the sections of the config.
sub configSections() is export {
    return readConfig().keys.sort;
}
