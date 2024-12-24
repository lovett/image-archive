unit package ImageArchive::Command;

use ImageArchive::Activity;
use ImageArchive::Workspace;

our sub finished() is export {
    my @results = walkWorkspaces('inactive');
    printSearchResults(@results);
}

our sub inprogress() is export {
    my @results = walkWorkspaces('active');
    printSearchResults(@results);
}
