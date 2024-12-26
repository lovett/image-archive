unit module ImageArchive::Command::Find;

use ImageArchive::Archive;
use ImageArchive::Config;
use ImageArchive::Util;

our proto run(Str $subcommand) {*};

multi sub run("finished") is export {
    my $root = appPath('root');
    my @results = walkWorkspaces("inactive");
    my $pager = getPager();
    printSearchResults(@results, $pager, $root);
}

multi sub run("inprogress") {
    my $root = appPath('root');
    my @results = walkWorkspaces("active");
    my $pager = getPager();
    printSearchResults(@results, $pager, $root);
}
