unit package ImageArchive::Command;

use ImageArchive::Activity;
use ImageArchive::Workspace;

our sub finished(Str $target) is export {
    my @results = walkWorkspaces('inactive');
    printSearchResults(@results);
}
