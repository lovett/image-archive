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

sub findNewestVersion(IO::Path $workspace) is export {
    my IO::Path $newest;

    for ($workspace.dir) -> $path {
        next unless $path.f;
        next unless $path.basename.starts-with: 'v';
        next if $newest && $newest.modified > $path.modified;
        $newest = $path;
    }

    return $newest;
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

    die ImageArchive::Exception::OrphanedWorkspace.new(
        :path($workspace)
    );
}

# See if a file exists within a workspace directory.
sub testPathExistsInWorkspace(IO::Path $file) is export {
    return if $file.parent.basename.ends-with('workspace');
    die ImageArchive::Exception::PathNotFoundInArchive.new(
        :path($file)
    );
}

#| Filter the list of workspaces.
sub walkWorkspaces(Str $flavor, Str $directory?) is export {
    my IO::Path $root = getPath('root');

    if ($directory) {
        $root = $root.add($directory);
    }

    my $counter = 0;

    clearStashByKey('searchresult');

    return gather {
        for walkArchiveDirs($root) -> $dir {
            next unless $dir.extension eq 'workspace';

            my IO::Path $master = findWorkspaceMaster($dir);
            my $newestVersion = findNewestVersion($dir);

            my $masterIsNewer = $master.modified >= $newestVersion.modified;

            next if $flavor eq 'active' and $masterIsNewer;
            next if $flavor eq 'inactive' and not $masterIsNewer;

            stashPath($master);

            take %(path => $master, modified => $newestVersion.modified.DateTime);
        }
    }
}
