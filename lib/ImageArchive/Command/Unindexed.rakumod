unit package ImageArchive::Command;

use Terminal::ANSIColor;

use ImageArchive::Archive;
use ImageArchive::Config;

our sub unindexed() is export {
    my $pager = getPager();

    my $counter = 0;

    for findUnindexed() -> $path {
        my $index = sprintf("%3d", ++$counter);
        $pager.in.printf(
            "%s | %s\n",
            colored($index, 'white on_red'),
            relativePath($path),
        );
    }

    unless $counter {
        say "No unindexed files.";
    }

    $pager.in.close;
}
