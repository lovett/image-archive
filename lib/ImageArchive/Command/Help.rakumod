unit module ImageArchive::Command::Help;

use ImageArchive::Config;

our sub run(Str $command) {
    unless ($command) {
        say $*USAGE;
        return;
    }

    my $shortSummary = $*USAGE.lines.grep( / ' ' $command ' ' / ).first;

    unless ($shortSummary) {
        say "Unknown command.";
        return;
    }

    say "Usage:";
    say $shortSummary;

    given $command {
        when 'search' {
            say explainSearchSyntax();
        }

        when 'setup' {
            say explainSetup();
        }
    }
}

sub explainSetup() {
    return qq:to/END/;

    The archive is where tagged images are kept. It is also home to
    the configuration file and the database.

    The default location is $*HOME/Archive.

    Specify a path to use a different location--either for personal
    preference, or to have multiple archives.

    If setting a path, also set the environment variable IA_ROOT.

    END
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
