unit package ImageArchive::Command;

use ImageArchive::Activity;

our sub filecount() is export {
    countFiles();
}
