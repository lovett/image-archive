unit module ImageArchive::Workspace;

use ImageArchive::Archive;
use ImageArchive::Config;
use ImageArchive::Database;
use ImageArchive::Exception;
use ImageArchive::Tagging;
use ImageArchive::Util;

# Symlink a workspace into a top-level folder for quick access.
sub addShortcut(IO::Path $dir) is export {
    my $shortcut = getShortcut($dir);
    symlink($dir, $shortcut) unless $shortcut ~~ :l;
    return $shortcut;
}

# Create an editable version of a file in the archive.
sub copyToWorkspace(IO::Path $source) is export {
    my $workspace = createWorkspace($source);
    my $destination = $workspace.add($source.basename);

    for lazy 0...99 -> $counter {
        my $candidate = sprintf(
            'v-%02d.%s',
            $counter,
            $source.extension
        );

        $destination = $workspace.add($candidate);

        last unless $destination ~~ :f;
    }

    $source.copy($destination);

    return $destination;
}

# Delete the workspace quick-access symlink.
sub removeShortcut(IO::Path $dir) is export {
    my $shortcut = getShortcut($dir);
    unlink($shortcut);
}

# Locate the editing workspace for a given file.
sub findWorkspace(IO::Path $file) is export {
    my $workspace = $file.extension('workspace');
    return $workspace;
}

# Create the editing workspace for a given file.
sub createWorkspace(IO::Path $file) is export {
    my $workspace = findWorkspace($file);

    $workspace.mkdir unless $workspace ~~ :d;

    addShortcut($workspace);

    return $workspace;
}

# Remove a workspace from the archive.
sub deportWorkspace(IO::Path $dir, IO $destinationDir, Bool $dryRun? = False) is export {
    my $destinationPath = $destinationDir.add($dir.basename);

    if ($destinationPath.IO ~~ :d) {
        die ImageArchive::Exception::DeportConflict.new(:path($destinationPath));
    }

    if ($dryRun) {
        wouldHaveDone("Move {relativePath($dir)} to {$destinationPath}");
        return;
    }

    rename($dir, $destinationPath);
    removeShortcut($dir);
}

# The path to the symlink providing quick access to a workspace.
sub getShortcut(IO::Path $dir) is export {
    my $shortcutRoot = getPath('root').add('_workspaces');
    my $flatPath = relativePath($dir).subst('/', '-', :g);
    my $shortcut = $shortcutRoot.add($flatPath);

    $shortcutRoot.mkdir unless $shortcutRoot ~~ :d;

    return $shortcut;
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
    my $workspace = createWorkspace($file);

    my $proc = run qqw{$command $workspace}, :err;
    my $err = $proc.err.slurp(:close);

    if ($proc.exitcode !== 0) {
        die ImageArchive::Exception::BadExit.new(:err($err));
    }
}

# See if a file exists within a workspace directory.
sub testPathExistsInWorkspace(IO::Path $file) is export {
    return if $file.parent.basename.ends-with('workspace');
    die ImageArchive::Exception::PathNotFoundInWorkspace.new;
}
