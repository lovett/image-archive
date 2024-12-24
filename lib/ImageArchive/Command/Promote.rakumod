unit module ImageArchive::Command::Promote;

use ImageArchive::Activity;

our sub run(Str $version, Bool :$dryrun) {
    promoteVersion($version.IO, $dryrun);
}
