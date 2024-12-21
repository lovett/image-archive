unit package ImageArchive::Command;

use ImageArchive::Activity;

our sub promote(Str $version, Bool :$dryrun) is export {
    promoteVersion($version.IO, $dryrun);
}
