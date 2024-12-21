unit package ImageArchive::Command;

use ImageArchive::Database;
use ImageArchive::Activity;
use ImageArchive::Color;

our sub colormatch(Str $target) is export {
    my @targets = resolveFileTarget($target);
    my @rgb = getAverageColor(@targets.first.IO);
    my @results = findBySimilarColor(@rgb, 'searchresult');
    printSearchResults(@results);
}
