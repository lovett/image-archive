unit module ImageArchive::Shell;

use ImageArchive::Config;
use ImageArchive::Exception;
use ImageArchive::Util;

# A mapping between commands and the kinds of arguments they accept.
our %commands = %(
    'color' => <file>,
    'colormatch' => <file>,
    'completion' => Nil,
    'deport' => <archivefile>,
    'filecount' => Nil,
    'finished' => Nil,
    'fixup' => Nil,
    'group' => Nil,
    'history' => <archivefile>,
    'import' => <file>,
    'inprogress' => Nil,
    'lastsearch' => Nil,
    'monthcount' => Nil,
    'promote' => <archivefile>,
    'reindex' => Nil,
    'reprompt' => <file>,
    'search' => Nil,
    'search:recent' => Nil,
    'setup' => <directory>,
    'show' => <file>,
    'tag' => <file keyword>,
    'todo' => Nil,
    'unindexed' => Nil,
    'untag' => Nil,
    'view' => <archivefile>,
    'visit' => <file>,
    'workon' => <archivefile>,
    'yearcount' => Nil,
);

sub commandFilter($argumentKind) {
    return ( $_ if %commands{$_}.grep($argumentKind) for %commands.keys )
}

sub writeShellCompletion() is export {
    my $root = getPath('root');
    my $appVersion = applicationVersion();

    my %contexts = readConfig('contexts');

    my @keywords = getKeywords();
    @keywords.append(contextNegationKeywords(%contexts));
    @keywords = @keywords.sort;

    my @aliases = readConfig('aliases').keys.sort;

    given %*ENV<SHELL>.IO.basename {
        when "fish" {
            writeFishCompletion(@keywords, @aliases, $appVersion)
        }

        default {
            die ImageArchive::Exception::UnsupportedShell.new;
        }
    }
}

sub writeFishCompletion(@keywords, @aliases, $appVersion) {
    my $root = getPath('root');
    my $completionFile = getPath('completion-fish');

    my $prefix = "complete -c {$*PROGRAM-NAME.IO.basename}";

    unless ($completionFile.parent.d) {
        mkdir($completionFile.parent);
    }

    spurt $completionFile, qq:to/END/;
    # This file was autogenerated by {$*PROGRAM-NAME.IO.absolute} version {$appVersion}

    # Test for command completion.
    # Commands can only appear as the first argument.
    function __fish_ia_command
        set -l tokens (commandline -ocp)
        test (count \$tokens) -eq 1
    end

    # Test for path completion inside archive.
    # When used, file paths can only appear as the second argument.
    function __fish_ia_file_in_archive
        set -l tokens (commandline -ocp)
        set -l validCommands { commandFilter('archivefile') }
        set -l currentCommand \$tokens[2]

        if test (count \$tokens) -gt 2
            return 1
        end

        if not contains \$currentCommand \$validCommands
            return 1
        end

        return 0
    end

    # Test for path completion outside archive.
    # When used, file paths can only appear as the second argument.
    function __fish_ia_file
        set -l tokens (commandline -ocp)
        set -l validCommands { commandFilter('file') }
        set -l currentCommand \$tokens[2]

        if test (count \$tokens) -gt 2
            return 1
        end

        if not contains \$currentCommand \$validCommands
            return 1
        end

        return 0
    end

    # Test for keyword completion.
    # When used, keywords can only appear from the third argument onward.
    function __fish_ia_keyword
        set -l tokens (commandline -ocp)
        set -l validCommands { commandFilter('keyword') }
        set -l currentCommand \$tokens[2]

        if test (count \$tokens) -lt 3
            return 1
        end

        if not contains \$currentCommand \$validCommands
            return 1
        end

        return 0
    end

    # Test for alias completion.
    # When used, aliases can only appear from the third argument onward.
    function __fish_ia_alias
        set -l tokens (commandline -ocp)
        set -l validCommands { commandFilter('alias') }
        set -l currentCommand \$tokens[2]

        if test (count \$tokens) -lt 3
            return 1
        end

        if not contains \$currentCommand \$validCommands
            return 1
        end

        return 0
    end

    # Test for directory completion.
    # When used, directories can only appear as the third argument.
    function __fish_ia_directory
        set -l tokens (commandline -ocp)
        set -l validCommands { commandFilter('directory') }
        set -l currentCommand \$tokens[2]

        if test (count \$tokens) -ne 2
            return 1
        end

        if not contains \$currentCommand \$validCommands
            return 1
        end

        return 0
    end

    # Autocomplete an archive file path.
    function __fish_ia_complete_archive_path
        set -l target
        set -l description
        switch (count \$argv)
            case 0
                # pass
            case 1
                set target "\$argv[1]"
            case 2 "*"
                set target "\$argv[1]"
                set description "\$argv[2]"
        end

        set -l archivetarget "{$root}/\$target"
        printf "%s\\t\$description\\n" (command ls -dp "\$archivetarget"*)
    end

    # Option completion
    {$prefix} --long-option=dryrun
    {$prefix} --long-option=help
    {$prefix} --long-option=version
    {$prefix} --long-option=archived

    # Command completion
    {$prefix} -n '__fish_ia_command' -a "{ %commands.keys.sort }"

    # Conditional completion
    {$prefix} -n '__fish_ia_alias' -a "{ @aliases }"

    {$prefix} -n '__fish_ia_directory' -a "(__fish_complete_directories)"

    {$prefix} -n '__fish_ia_file' -a "(__fish_complete_path)"
    {$prefix} -n '__fish_ia_file_in_archive' -a "(__fish_ia_complete_archive_path)"

    {$prefix} -n '__fish_ia_keyword' -a "{@keywords}"

    END

    say "Wrote $completionFile"
}
