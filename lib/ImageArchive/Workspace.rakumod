unit module ImageArchive::Workspace;

use ImageArchive::Archive;
use ImageArchive::Config;
use ImageArchive::Database;
use ImageArchive::Exception;
use ImageArchive::Tagging;
use ImageArchive::Util;

# Add a text file to a workspace for capturing notes and progress.
sub addWorkspaceLog(IO::Path $workspace) returns Nil {
    my $log = findWorkspaceLog($workspace);

    unless $log.f {
        my $dayNames = <Sun Mon Tue Wed Thu Fri Sat Sun>;
        my $template = %?RESOURCES<history.org>.IO.slurp;
        $template = $template.subst('@@WORKSPACE@@', relativePath($workspace));

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

# Create an editable version of a file in the archive.
sub copyToWorkspace(IO::Path $source) returns IO::Path is export {
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

    return $workspace;
}

# The history file within a given workspace.
sub findWorkspaceLog(IO::Path $workspace) returns IO::Path is export {
    return $workspace.add("history.org");
}

# Locate the editing workspace for a given file.
sub findWorkspace(IO::Path $file) is export {
    testPathExistsInArchive($file);
    my $workspace = $file.extension('workspace');
    return $workspace;
}

# Create the editing workspace for a given file.
sub openWorkspace(IO::Path $file) is export {
    my $workspace = findWorkspace($file);

    unless $workspace ~~ :d {
        mkdir($workspace);
        addWorkspaceLog($workspace);
    }

    return $workspace;
}

# Transfer a workspace to a new location within or outside the archive.
sub moveWorkspace(IO::Path $workspace, IO::Path $destination, Bool $dryrun? = False) is export {
    my $destinationPath = $destination.add($workspace.basename);

    if ($destinationPath.IO ~~ :d) {
        die ImageArchive::Exception::PathConflict.new(:path($destinationPath));
    }

    if ($dryrun) {
        wouldHaveDone("Move {relativePath($workspace)} to {$destinationPath}");
        return;
    }

    rename($workspace, $destinationPath);

    my $log = findWorkspaceLog($destinationPath);

    if ($log) {
        my $originalRelativePath = relativePath($workspace);
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

# See if a file exists within a workspace directory.
sub testPathExistsInWorkspace(IO::Path $file) is export {
    return if $file.parent.basename.ends-with('workspace');
    die ImageArchive::Exception::PathNotFoundInArchive.new(
        :path($file)
    );
}
