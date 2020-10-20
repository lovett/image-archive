unit module ImageArchive::Shell;

use Terminal::ANSIColor;

use ImageArchive::Config;

sub writeShellCompletion(Str $scriptVersion) is export {
    my $root = getPath('root');

    my @sections = configSections();
    my %contexts = readConfig('contexts');
    my %aliases = readConfig('aliases');

    my $keywords = ($_ unless $_ ~~ any <_ aliases prompts contexts> for @sections) (|) ('no' ~ $_ for @sections);

    given %*ENV<SHELL>.IO.basename {

        when "fish" {
            my $completionFile = getPath('completion-fish');

            my $prefix = "complete -c {$*PROGRAM-NAME.IO.basename}";

            unless ($completionFile.parent.d) {
                mkdir($completionFile.parent);
            }

            spurt $completionFile, qq:to/END/;
            # This file was autogenerated by {$*PROGRAM-NAME.IO.absolute} version {$scriptVersion}

            {$prefix} --no-files --long-option=dryrun
            {$prefix} --no-files --long-option=help
            {$prefix} --no-files --long-option=version

            {$prefix} --arguments=completion

            {$prefix} --arguments=count
            {$prefix} --arguments=dbshell

            {$prefix} --arguments=deport
            {$prefix} --condition="__fish_seen_subcommand_from deport" --arguments="(__fish_complete_subcommand)"

            {$prefix} --arguments=import
            {$prefix} --condition="__fish_seen_subcommand_from import" --arguments="(__fish_complete_subcommand)"

            {$prefix} --arguments=reprompt
            {$prefix} --condition="__fish_seen_subcommand_from reprompt" --arguments="(__fish_complete_subcommand)"

            {$prefix} --arguments=search

            {$prefix} --arguments=setup
            {$prefix} --condition="__fish_seen_subcommand_from setup" --arguments="(__fish_complete_subcommand)"

            {$prefix} --arguments=stats

            {$prefix} --arguments=tag
            {$prefix} --condition="__fish_seen_subcommand_from tag" --arguments="(__fish_complete_path) {$keywords.keys.sort.join(' ')}"

            {$prefix} --arguments=trash
            {$prefix} --condition="__fish_seen_subcommand_from trash" --arguments="(__fish_complete_subcommand)"

            {$prefix} --arguments=untag
            {$prefix} --condition="__fish_seen_subcommand_from untag" --arguments="(__fish_complete_path) {%aliases.keys.sort.join(' ')} {$keywords.keys.sort.join(' ')}"

            {$prefix} --arguments=view
            {$prefix} --condition="__fish_seen_subcommand_from view" --arguments="(__fish_complete_path) {%aliases.keys.sort.join(' ')}"
            END

            say "Wrote $completionFile"
        }

        default {
            note colored("Sorry, shell completion isn't available for your shell", "yellow bold");
        }
    }
}
