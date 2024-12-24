unit module ImageArchive::Command::History;

use ImageArchive::Activity;

our sub run(Str $target) {
    my @targets = resolveFileTarget($target);
    printHistory(@targets);
}
