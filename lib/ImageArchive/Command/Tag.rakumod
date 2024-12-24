unit module ImageArchive::Command::Tag;

use Terminal::ANSIColor;

use ImageArchive::Activity;
use ImageArchive::Config;
use ImageArchive::Exception;

our sub run(Str $target, Bool :$dryrun, *@keywords) {
    my @targets = resolveFileTarget($target);
    tagAndImport(@targets, @keywords, $dryrun);

    CATCH {
        when ImageArchive::Exception::MissingContext {
            note colored($_.message, 'red');
            suggestContextKeywords($_.offenders);
            exit 1;
        }
    }
}

sub suggestContextKeywords(@contexts) {
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
