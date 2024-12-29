unit module ImageArchive::Command::Find;

use ImageArchive::Archive;
use ImageArchive::Config;
use ImageArchive::Util;

our proto run(Str $subcommand) {*};

multi sub make-it-so("finished") is export {
    my $root = appPath('root');
    my @results = walkWorkspaces("inactive");
    my $pager = getPager();
    printSearchResults(@results, $pager, $root);
}

sub make-it-so("inprogress") is export {
    my $root = appPath('root');
    my @results = walkWorkspaces("active");
    my $pager = getPager();
    printSearchResults(@results, $pager, $root);
}
