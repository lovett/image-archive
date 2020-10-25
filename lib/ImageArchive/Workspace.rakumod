unit module ImageArchive::Workspace;

# Locate the editing workspace for a given file.
# Create it if doesn't exist.
sub findWorkspace(IO::Path $file) is export {
    my $workspace = $file.extension('versions');

    $workspace.mkdir unless $workspace ~~ :d;

    return $workspace;
}

# Copy an archive file into its corresponding workspace.
# The source file is unchanged.
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

# Move a file out of the workspace.
sub workspaceExport(IO::Path $file) is export {
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

# Enumerate the contents of a workspace.
sub listWorkspace(IO::Path $workspace) is export {
}

# Tag a workspace file with the tags from the current version.
sub transferTags(IO::Path $recipient) is export {
}
