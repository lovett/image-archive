unit module ImageArchive::Command::Unindexed;

use Terminal::ANSIColor;

use ImageArchive::Archive;
use ImageArchive::Config;
use ImageArchive::Util;

our sub make-it-so() {
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
