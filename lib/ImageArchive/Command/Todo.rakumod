unit module ImageArchive::Command::Todo;

use ImageArchive::Activity;

our sub run(Str $directory?) {
    searchLogs(/TODO/, $directory);
}
