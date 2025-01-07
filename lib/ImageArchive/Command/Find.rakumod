unit module ImageArchive::Command::Find;

use Terminal::ANSIColor;

use ImageArchive::Archive;
use ImageArchive::Config;
use ImageArchive::Util;

multi sub make-it-so("finished") is export {
    my $root = appPath('root');
    my @results = walkWorkspaces("inactive");
    my $pager = getPager();
    printSearchResults(@results, $pager, $root);
}

multi sub make-it-so("inprogress") is export {
    my $root = appPath('root');
    my @results = walkWorkspaces("active");
    my $pager = getPager();
    printSearchResults(@results, $pager, $root);
}

multi sub make-it-so("unindexed") is export {
    my $root = appPath("root");
    my $pager = getPager();
    my $counter = 0;

    for findUnindexed() -> $path {
        my $index = sprintf("%3d", ++$counter);
        $pager.in.printf(
            "%s | %s\n",
            colored($index, 'white on_red'),
            relativePath($path, $root),
        );
    }

    unless $counter {
        say "No unindexed files.";
    }

    $pager.in.close;
}
