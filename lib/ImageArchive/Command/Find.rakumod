unit module ImageArchive::Command::Find;

use ImageArchive::Activity;
use ImageArchive::Workspace;

our proto run(Str $subcommand) {*};

multi sub run("finished") is export {
    my @results = walkWorkspaces("inactive");
    printSearchResults(@results);
}

!multi sub run("inprogress") {
    my @results = walkWorkspaces("active");
    printSearchResults(@results);
}
