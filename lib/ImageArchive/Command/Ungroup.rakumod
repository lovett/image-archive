unit module ImageArchive::Command::Ungroup;

use ImageArchive::Activity;

our sub run(Str $target, Str $name, Bool :$dryrun) {
    my @targets = resolveFileTarget($target);
    ungroupFiles(@targets, $name, $dryrun);
}
