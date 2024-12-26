unit module ImageArchive::Command::Color;

use Terminal::ANSIColor;

use ImageArchive::Archive;
use ImageArchive::Color;
use ImageArchive::Config;
use ImageArchive::Database;
use ImageArchive::Tagging;
use ImageArchive::Util;

our sub run(Str $target) {
    my @targets = resolveFileTarget($target);
    printColorTable(@targets);
}

#| Print a mapping of file paths to RGB triples.
sub printColorTable(@paths) is export {
    my $root = appPath("root");
    my $pager = getPager();

    my $colspec = "%-6s | %-11s | %s\n";

    $pager.in.say: "";
    $pager.in.printf($colspec, 'Swatch', 'RGB', 'Path');
    $pager.in.say: "-" x 72;

    for @paths -> $path {
        my %tags = getTags($path, 'AverageRGB');
        my $rgb = sprintf('%-11s', %tags<AverageRGB> || 'unknown');

        $pager.in.printf(
            $colspec,
            colored('      ', "white on_$rgb"),
            $rgb,
            relativePath($path, $root)
        );
    }

    $pager.in.say: "";
    $pager.in.close;
}
