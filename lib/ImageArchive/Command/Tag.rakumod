unit module ImageArchive::Command::Tag::Tag;

use ImageArchive::Activity;

our sub run(Str $target, Bool :$dryrun, *@keywords) {
    my @targets = resolveFileTarget($target);
    tagAndImport(@targets, @keywords, $dryrun);
}
