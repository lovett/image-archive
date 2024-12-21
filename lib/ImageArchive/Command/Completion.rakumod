unit package ImageArchive::Command;

use ImageArchive::Shell;

our sub completion() is export {
    writeShellCompletion();
}
