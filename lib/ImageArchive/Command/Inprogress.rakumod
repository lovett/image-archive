unit package ImageArchive::Command;

use ImageArchive::Workspace;

our sub inprogress() is export {
    my @results = walkWorkspaces('active');
    printSearchResults(@results);
}
