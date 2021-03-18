unit module ImageArchive::Workspace;

use ImageArchive::Archive;
use ImageArchive::Config;
use ImageArchive::Database;
use ImageArchive::Exception;
use ImageArchive::Tagging;
use ImageArchive::Util;

enum WorkspaceState is export <Closed Opened>;

# Add a text file to a workspace for capturing notes and progress.
sub addWorkspaceLog(IO::Path $dir) returns Nil {
    my $log = findWorkspaceLog($dir);

    unless $log.f {
        my $dayNames = <Sun Mon Tue Wed Thu Fri Sat Sun>;
        my $template = %?RESOURCES<history.org>.IO.slurp;
        $template = $template.subst('@@WORKSPACE@@', relativePath($dir));

        $template = $template.subst(
            '@@DATE@@',
            Date.today(
                formatter => {
                    sprintf("%04d-%02d-%02d %s", .year, .month, .day, $dayNames[.day-of-week]);
                }
            )
        );
        spurt $log, $template;
    }

    return Nil;
}

# Print the contents of a workspace log to stdout.
sub catWorkspaceLog(IO::Path $file) returns Supply is export {
    my $workspace = findWorkspace($file);

    my $log = findWorkspaceLog($workspace);

    return unless ($log ~~ :f);

    supply for $log.lines -> $line {
        next unless $line.trim;
        next if $line.starts-with('#');
        $line.subst(/\*+\s/, "").emit;
        "\n".emit if $line.starts-with('*');
    }
}

# Convert an opened workspace to a closed workspace
sub closeWorkspace(IO::Path $workspace, Bool $dryRun? = False) returns Nil is export {
    testPathIsWorkspace($workspace);

    my $archive = $workspace.extension('archive');

    if ($dryRun) {
        wouldHaveDone("Rename {$workspace} to {$archive}");
        return;
    }

    rename($workspace, $archive);
}

# Create an editable version of a file in the archive.
sub copyToWorkspace(IO::Path $source) returns Nil is export {
    my $workspace = openWorkspace($source);

    my $sourceHash = hashFile($source);

    my $workspaceFile;

    for lazy 0...99 -> $counter {
        my $candidate = sprintf(
            'v-%02d.%s',
            $counter,
            $source.extension
        );

        $workspaceFile = $workspace.add($candidate);

        if ($workspaceFile ~~ :f) {
            my $workspaceFileHash = hashFile($workspaceFile);
            if ($workspaceFileHash eq $sourceHash) {
                $workspaceFile = Nil;
                last;
            }
        }

        last unless $workspaceFile ~~ :f;
    }

    if ($workspaceFile) {
        $source.copy($workspaceFile);
        $workspaceFile.chmod(0o644);
    }

    return Nil;
}

# Open history.org in an editor.
sub editWorkspaceLog(IO::Path $file) is export {
    my $workspace = findWorkspace($file);
    my $log = findWorkspaceLog($workspace);

    testPathExistsInWorkspace($log);

    if %*ENV<EDITOR> {
        shell "{%*ENV<EDITOR>} {$log}";
        return;
    }

    say "The workspace history file could not be auto-opened for editing.";
    say $log.Str;
}

# The history file within a given workspace.
sub findWorkspaceLog(IO::Path $workspace) returns IO::Path is export {
    return $workspace.add("history.org");
}

# Locate the editing workspace for a given file.
sub findWorkspace(IO::Path $file) is export {
    my $workspace = $file.extension('workspace');
    return $workspace;
}

# Create the editing workspace for a given file.
sub openWorkspace(IO::Path $file) is export {
    my $workspace = findWorkspace($file);
    my $archive = $workspace.extension('archive');

    if ($archive ~~ :d) {
        rename($archive, $workspace);
    }

    $workspace.mkdir unless $workspace ~~ :d;

    addWorkspaceLog($workspace);

    return $workspace;
}

# Transfer a workspace to a new location within or outside the archive.
sub moveWorkspace(IO::Path $dir, IO $destinationDir, Bool $dryRun? = False) is export {
    my $destinationPath = $destinationDir.add($dir.basename);

    if ($destinationPath.IO ~~ :d) {
        die ImageArchive::Exception::PathConflict.new(:path($destinationPath));
    }

    if ($dryRun) {
        wouldHaveDone("Move {relativePath($dir)} to {$destinationPath}");
        return;
    }

    rename($dir, $destinationPath);

    my $log = findWorkspaceLog($destinationPath);

    if ($log) {
        my $originalRelativePath = relativePath($dir);
        my $destinationRelativePath = relativePath($destinationPath);

        my $tmp = open $log ~ '.tmp', :w;

        for $log.lines -> $line {
            $tmp.say: $line.subst($originalRelativePath, $destinationRelativePath);
        }

        $tmp.close;
        rename($tmp, $log);
    }
}

# Locate the file associated with the workspace.
sub findWorkspaceMaster(IO::Path $workspace) is export {

    my $workspaceBasename = $workspace.extension('').basename;

    for walkArchive($workspace.parent) -> $path {
        return $path if $path.basename.starts-with($workspaceBasename);
    }

    die ImageArchive::Exception::PathNotFoundInArchive.new;
}

# Locate lines in log files matching a regex.
sub searchLogs(IO::Path $root, Regex $matcher) returns Supply is export {
    supply {
        for walkArchive($root, /history\.org/) -> $path {
            for $path.lines.grep($matcher) -> $line {
                emit(($path, $line));
            }
        }
    }
}

# List the workspaces in the archive
sub walkWorkspaces(IO::Path $origin, WorkspaceState $state) is export {
    my $extension = 'workspace';

    if ($state eq Closed) {
        $extension = 'archive';
    }

    supply for ($origin.dir.sort) {
        next when :f;
        when .extension eq $extension {
            my $master = findWorkspaceMaster($_);
            my $relativeMaster = relativePath($master);
            stashWorkspace($relativeMaster);
            .emit;
        }
        when :d { .emit for walkWorkspaces($_, $state) }
    }
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
    $newMaster.chmod(0o400);
}

# See if a file exists within a workspace directory.
sub testPathExistsInWorkspace(IO::Path $file) is export {
    return if $file.parent.basename.ends-with('workspace');
    die ImageArchive::Exception::PathNotFoundInWorkspace.new;
}

# See if a path refers to a workspace diretory.
sub testPathIsWorkspace(IO::Path $path) is export {
    return if $path.extension eq 'workspace';
    die ImageArchive::Exception::NotAWorkspace.new;
}
