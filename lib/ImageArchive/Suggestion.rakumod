unit module ImageArchive::Suggestion;

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
