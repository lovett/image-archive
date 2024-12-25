unit module ImageArchive::Command::Group;

use ImageArchive::Archive;
use ImageArchive::Database;
use ImageArchive::Tagging;

#| Add a JobRef tag, which is a keyword describing a project or workflow.
our sub run(Str $target, Str $name, Bool :$dryrun) {
    my @targets = resolveFileTarget($target);

    # Skipping Id and URL for the moment and only using Name.
    my %tags = group => "\{Name=$name\}";

    for @targets -> $target {
        tagFile($target, %tags, $dryrun);

        next if $dryrun;

        if (isArchiveFile($target)) {
            indexFile($target);
        }
    }
}
