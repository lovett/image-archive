unit module ImageArchive::Command::Ungroup;

use ImageArchive::Archive;
use ImageArchive::Config;
use ImageArchive::Database;
use ImageArchive::Tagging;

#| Remove a JobRef tag.
sub make-it-so(Str $target, Str $name, Bool $dryrun) is export {
    my @targets = resolveFileTarget($target);
    my %aliases = readConfig('aliases');
    my $formalTag = %aliases<group>;

    for @targets -> $target {
        commitTags($target, "-{$formalTag}-=\{Name=$name\}".List, $dryrun);

        next if $dryrun;

        if (isArchiveFile($target)) {
            indexFile($target);
        }
    }
}
