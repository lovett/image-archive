unit module ImageArchive::Command::Colormatch;

use ImageArchive::Database;
use ImageArchive::Activity;
use ImageArchive::Archive;
use ImageArchive::Color;

our sub run(Str $target) {
    my @targets = resolveFileTarget($target);
    my @rgb = getAverageColor(@targets.first.IO);
    my @results = findBySimilarColor(@rgb, 'searchresult');
    printSearchResults(@results);
}
