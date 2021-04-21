unit module ImageArchive::Hints;

use Terminal::ANSIColor;

use ImageArchive::Config;

sub suggestContextKeywords(@contexts) is export {
    my %contexts = readConfig('contexts');

    my %suggestionContexts = @contexts Z=> %contexts{@contexts};

    say "";

    for %suggestionContexts.kv -> $context, $aliases {
        my @keywords = keywordsInContext($context);
        say colored("{$context} keywords", 'cyan underline') ~ "\n" ~ @keywords.sort.join(", ");
        say "To disable: no{$context}";
        say "";
    }
}

sub suggestFilters() is export {
    my %filters = readConfig('filters');
    my @filters = %filters.keys.sort;

    say "";
    say colored('Filters', 'cyan underline') ~ "\n" ~ @filters.join(", ");
}

sub explainSyntax(Str $command) is export {
    my $shortSummary = $*USAGE.lines.grep( / ' ' $command ' ' / ).first;

    unless ($shortSummary) {
        die "Unknown command.";
    }

    say "Usage:";
    say $shortSummary;

    given $command {
        when 'search' {
            say explainSearchSyntax();
        }

        when / ^ untag / {
            say explainAllfiles();
        }
    }
}

sub explainSearchSyntax() {
    my %filters = readConfig('filters');
    my @filters = %filters.keys.sort;

    return qq:to/END/;

    FILTERS
      Search terms are matched against the tag metdata stored in the
      database. By default, these matches are unrestricted and all tags
      are considered (as well as tag names themselves).

      To narrow term matching to specific tags, prefix the term with one
      of the filters defined in the config followed by a ":". For example:

        author:john smith

      A filter can have the same name as a tag, but it doesn't have to.

      Filters are defined in the configuration file. The following filters
      are available:
        {@filters.join("\n  ")}

    ORDERING
      Searches are orderd by file path by default, but can instead be
      ordered by filename or series name and number. The search order is
      specified as a filter:

      order:series
      order:filename

    SPECIAL TERM: unknown
      To locate files that do not contain a tag, use the special term "unknown":

      author:unknown
      This will match any file that does not have an author tag.

    SPECIAL TERM: recent
      A search consisting of this term will bring back the most recently added
      files. Use --limit to control how many files are shown.

    SPECIAL TERM: lastimport
      Equivalent to recent with --limit=1

    END
}

sub explainAllfiles() {

    return qq:to/END/;

    SPECIAL TERM: allfiles
    To apply this command to all files within the archive, specify "allfiles"
    as the target.

    END
}
