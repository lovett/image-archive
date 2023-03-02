unit module ImageArchive::Setup;

use ImageArchive::Config;
use ImageArchive::Shell;
use ImageArchive::Util;

# Establish the SQLite database.
sub createDatabase() is export {
    my $dbPath = getPath('database');

    return if $dbPath.f;

    my $schemaPath = %?RESOURCES<schema-sqlite.sql>.absolute;

    my $proc = run 'sqlite3', $dbPath, :in;
    $proc.in.say(".read {$schemaPath}");
    $proc.in.close;

    CATCH {
        when X::Proc::Unsuccessful {
            my $err = "Failed to apply database schema.";
            ImageArchive::Exception::BadExit.new(:err($err)).throw;
        }
    }
}

sub setup(Str $path?) is export {
    my $root = 'Archive'.IO;
    if (defined $path) {
        unless ($path.IO.d) {
            note "That path is not a directory. Cannot proceed.";
            exit 1;
        }

        if ($path.IO.dir) {
            note "That directory is not empty. Cannot proceed.";
            exit 1;
        }

        $root = $path.IO.resolve;
    }

    if (not defined $path) {
        if ($root.d and $root.dir) {
            note "A directory named {$root.basename} already exists and is not empty. Cannot proceed.";
            exit 1;
        }

        confirm("Create {$root.absolute}?");
        mkdir($root);
    }

    writeApplicationConfig($root.IO);
    writeArchiveConfig();
    createDatabase();
    writeShellCompletion();
}

# Create the file that defines application-wide settings.
sub writeApplicationConfig(IO::Path $root) is export {
    my $target = getPath('appconfig');

    return if $target ~~ :f;

    unless ($target.IO.parent.d) {
        mkdir($target.IO.parent);
    }

    spurt $target, qq:to/END/;
    ; This is the application configuration for Image Archive (ia),
    ; defining global settings.
    ;
    ; For archive-specific settings, see the file conf.ini in the archive
    ; root.

    ; The location of the archive as an absolute path.
    root = {$root.absolute}

    END

    say "Wrote {$target}";
}

# Create the file that defines archive-specific settings.
sub writeArchiveConfig() is export {
    my $target = getPath('config');

    my $templatePath = %?RESOURCES<config.ini>.absolute;

    return if $target ~~ :f;

    copy($templatePath, $target.absolute);

    say "Wrote {$target.absolute}";
}
