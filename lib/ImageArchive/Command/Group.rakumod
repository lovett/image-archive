unit module ImageArchive::Command::Group;

use ImageArchive::Activity;

our sub run(Str $target, Str $name, Bool :$dryrun) {
    my @targets = resolveFileTarget($target);
    groupFiles(@targets, $name, $dryrun);
}
