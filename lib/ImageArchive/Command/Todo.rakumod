unit module ImageArchive::Command::Todo::Todo;

use ImageArchive::Activity;

our sub run(Str $directory?) {
    searchLogs(/TODO/, $directory);
}
