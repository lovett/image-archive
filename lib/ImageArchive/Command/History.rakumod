unit package ImageArchive::Command;

use ImageArchive::Activity;

our sub history(Str $target) is export {
    my @targets = resolveFileTarget($target);
    printHistory(@targets);
}
