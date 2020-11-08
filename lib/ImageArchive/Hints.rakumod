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
    say colored('Filters', 'cyan underline') ~ "\n" ~ @filters.sort.join(", ");
}

sub explainSearchSynax() is export {
    return q:to/END/;

    FILTERS
    Search terms are matched against the tag metdata stored in the
    database. By default, these matches are unrestricted and all tags
    are considered (as well as tag names themselves).

    To narrow term matching to specific tags, prefix the term with one
    of the filters defined in the config followed by a ":". For example:

    author:john smith

    This matches "john smith" but only within the author tag.

    ORDERING
    Searches are orderd by file path by default, but can instead be
    ordered by filename or series name and number. The search order is
    specified as a filter:

    order:series
    order:filename

    UNKNOWNS
    To locate files that do not contain a tag, use the special term "unknown":

    author:unknown

    This matches any file that does not have an author tag.

    END
}
