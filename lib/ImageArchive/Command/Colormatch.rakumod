unit module ImageArchive::Command::Colormatch;

use ImageArchive::Archive;
use ImageArchive::Color;
use ImageArchive::Config;
use ImageArchive::Database;
use ImageArchive::Util;

our sub run(Str $target) {
    my $root = appPath('root');
    my @targets = resolveFileTarget($target);
    my @rgb = getAverageColor(@targets.first.IO);
    my @results = findBySimilarColor(@rgb, 'searchresult');
    my $pager = getPager();
    printSearchResults(@results, $pager, $root);
}
