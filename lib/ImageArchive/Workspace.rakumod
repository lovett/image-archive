unit module ImageArchive::Workspace;

use ImageArchive::Archive;
use ImageArchive::Database;
use ImageArchive::Exception;
use ImageArchive::Tagging;
use ImageArchive::Util;

# Locate the editing workspace for a given file.
sub findWorkspace(IO::Path $file) is export {
    my $workspace = $file.extension('versions');

    $workspace.mkdir unless $workspace ~~ :d;
    return $workspace;
}

# Copy an archive file into its corresponding workspace.
sub workspaceImport(IO::Path $source) is export {
    my $workspace = findWorkspace($source);
    my $destination = $workspace.add($source.basename);

    for lazy 1...99 -> $counter {
        last unless $destination ~~ :f;
        my $candidate = sprintf(
            '%s-%02d.%s',
            $source.extension('').basename,
            $counter,
            $source.extension
        );

        $destination = $workspace.add($candidate);
    }

    $source.copy($destination);

    return $destination;
}

# Locate the file associated with the workspace.
sub findWorkspaceMaster(IO::Path $workspace) {

    my $workspaceBasename = $workspace.extension('').basename;

    for walkArchive($workspace.parent) -> $path {
        return $path if $path.basename.starts-with($workspaceBasename);
    }

    die ImageArchive::Exception::PathNotFoundInArchive.new;
}

# Move a file out of the workspace.
sub workspaceExport(IO::Path $file, Bool $dryRun? = False) is export {
    testPathExistsInWorkspace($file.IO);

    my $master = findWorkspaceMaster($file.parent);
    my $newMaster = $master.extension($file.extension);

    if ($dryRun) {
        wouldHaveDone("{$file} becomes {$newMaster}");
        return;
    }

    transferTags($master, $file);
    deleteAlts($master);
    deindexFile($master);
    unlink($master);

    rename($file, $newMaster);
    indexFile($newMaster);
    generateAlts($newMaster);
    chmod($newMaster, 0o400);
}

# Run a command to display the workspace.
sub openWorkspace(IO::Path $file, Str $command) is export {
    my $workspace = findWorkspace($file);

    my $proc = run qqw{$command $workspace}, :err;
    my $err = $proc.err.slurp(:close);

    if ($proc.exitcode !== 0) {
        die ImageArchive::Exception::BadExit.new(:err($err));
    }
}

# See if a file exists within a workspace directory.
sub testPathExistsInWorkspace(IO::Path $file) is export {
    return if $file.parent.basename.ends-with('versions');
    die ImageArchive::Exception::PathNotFoundInWorkspace.new;
}
