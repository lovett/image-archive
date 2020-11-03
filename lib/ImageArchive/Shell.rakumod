unit module ImageArchive::Shell;

use Terminal::ANSIColor;

use ImageArchive::Config;

# A mapping between commands and the kinds of arguments they accept.
our %commands = %(
    'alts' => Nil,
    'completion' => Nil,
    'count' => Nil,
    'dbshell' => Nil,
    'deport' => <file>,
    'dump' => <alias file>,
    'import' => <file>,
    'promote' => <file>,
    'reimport' => Nil,
    'reprompt' => <file>,
    'search' => Nil,
    'setup' => <directory>,
    'tag' => <file keyword>,
    'untag' => <file keyword>,
    'untag:alias' => <alias file>,
    'untag:keyword' => <file>,
    'untag:value' => <alias fil>,
    'version' => <file>,
    'view' => <file>
);

sub commandFilter($argumentKind) {
    return ( $_ if %commands{$_}.grep($argumentKind) for %commands.keys )
}

sub writeShellCompletion(Str $scriptVersion) is export {
    my $root = getPath('root');

    my %contexts = readConfig('contexts');

    my @keywords = getKeywords();
    @keywords.append(contextNegationKeywords(%contexts));
    @keywords = @keywords.sort;

    my @aliases = readConfig('aliases').keys.sort;

    given %*ENV<SHELL>.IO.basename {
        when "fish" {
            writeFishCompletion(@keywords, @aliases, $scriptVersion)
        }

        default {
            note colored("Sorry, shell completion isn't available for your shell", "yellow bold");
        }
    }
}

sub writeFishCompletion(@keywords, @aliases, $scriptVersion) {
    my $completionFile = getPath('completion-fish');

    my $prefix = "complete -c {$*PROGRAM-NAME.IO.basename}";

    unless ($completionFile.parent.d) {
        mkdir($completionFile.parent);
    }

    spurt $completionFile, qq:to/END/;
    # This file was autogenerated by {$*PROGRAM-NAME.IO.absolute} version {$scriptVersion}

    # Test for command completion.
    # Commands can only appear as the first argument.
    function __fish_ia_command
        set -l tokens (commandline -ocp)
        test (count \$tokens) -eq 1
    end

    # Test for file path completion.
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

    # Disable file completion by default.
    {$prefix} -f

    # Option completion
    {$prefix} --long-option=dryrun
    {$prefix} --long-option=help
    {$prefix} --long-option=version

    # Command completion
    {$prefix} -n '__fish_ia_command' -a "{ %commands.keys.sort }"

    # Conditional completion
    {$prefix} -n '__fish_ia_alias' -a "{ @aliases }"

    {$prefix} -n '__fish_ia_directory' -a "(__fish_complete_directories)"

    {$prefix} -n '__fish_ia_file' -a "(__fish_complete_path)"

    {$prefix} -n '__fish_ia_keyword' -a "{@keywords}"

    END

    say "Wrote $completionFile"
}
