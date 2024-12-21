unit package ImageArchive::Command;

use ImageArchive::Database;
use ImageArchive::Activity;

our sub lastsearch() is export {
    my @results = dumpStash('searchresult');
    printSearchResults(@results);
}
