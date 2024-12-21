unit package ImageArchive::Command;

use ImageArchive::Activity;

our sub todo(Str $directory?) is export {
    searchLogs(/TODO/, $directory);
}
