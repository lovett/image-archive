unit module ImageArchive::Tagging;

use Terminal::ANSIColor;

use ImageArchive::Color;
use ImageArchive::Config;
use ImageArchive::Exception;
use ImageArchive::Util;

# Prompt for tag values that are unique to the image.
sub askQuestions(IO::Path $target) is export {
    my %prompts = readConfig('prompts');
    my %currentTags = readRawTags($target, %prompts.keys);
    my %answers;

    say '';
    say colored('TAGGING NOTES', 'magenta');
    say q:to/END/;
    - The current value is shown in brackets if there is one.
    - Type - to remove the current value and discard the tag.
    - Leave the tag blank to keep it as-is.
    - If the current value is a list, the new value will be appended.
      Otherwise the current value will be replaced.
    END

    for %prompts.sort(*.key) {
        my $promptText = "{$_.value}: ";
        my $currentValue = %currentTags{.key};
        if $currentValue {
            unless $currentValue.starts-with: '[' {
                $currentValue = "[$currentValue]";
            }

            $promptText = sprintf(
                "%s %s: ",
                .value,
                colored($currentValue, 'yellow')
            );
        }

        my $answer = prompt $promptText;
        $answer .= trim;
        next unless $answer;
        %answers{$_.key} = ($_.trim for $answer.split(','))
    }

    return %answers;
}

# Write one or more tags to a file via exiftool.
sub commitTags(IO $file, @commands, Bool $dryrun? = False) is export {
    my $configPath = %?RESOURCES<exiftool.config>.IO.absolute;

    if ($dryrun) {
        wouldHaveDone("exiftool -config {$configPath} -ignoreMinorErrors {@commands} {$file}");
        return;
    }

    my $proc = run qqw{exiftool -config $configPath -ignoreMinorErrors}, @commands, $file.Str, :out, :err;

    my $err = $proc.err.slurp(:close);
    my $out = $proc.out.slurp(:close);

    if ($proc.exitcode !== 0) {
        restoreOriginal($file);
        die ImageArchive::Exception::BadExit.new(:err($err));
    }

    if ($err) {
        restoreOriginal($file);
        die ImageArchive::Exception::BadExit.new(:err($err));
    }

    removeOriginal($file);
}

# Extract a tag specified from a file.
sub readRawTag(IO $file, $tag) is export {
    my %aliases = readConfig('aliases');

    my $formalTag = %aliases{$tag} || $tag;

    my $proc = run <exiftool -s3 -n>, "-{$formalTag}", $file.Str, :out, :err;
    my $err = $proc.err.slurp(:close);
    my $out = $proc.out.slurp(:close);

    if ($proc.exitcode !== 0) {
        die ImageArchive::Exception::BadExit.new(:err($err));
    }

    return chomp($out);
}

# Extract tags from a file in a human-readable format.
sub readTags(IO::Path $file, @tags) is export {
    my @tagArguments = @tags.map({ '-' ~ $_});

    my $proc = run <exiftool -G -struct>, @tagArguments, $file.Str, :out, :err;
    my $err = $proc.err.slurp(:close);
    my $out = $proc.out.slurp(:close);

    if ($proc.exitcode !== 0) {
        die ImageArchive::Exception::BadExit.new(:err($err));
    }

    return chomp($out);
}

# Extract multiple tags from a file.
#
# This is the file-oriented equivalent of Database::getTags.
sub readRawTags(IO $file, @tags, Str $flags = '') is export {
    my %aliases = readConfig('aliases');
    my @formalTags;
    for @tags -> $tag {
        @formalTags.push('-' ~ (%aliases{$tag} || $tag));
    }

    # First run: collect unstructured values.
    #
    # This handles the majority of tags by presuming they hold scalar
    # values.
    my $proc = run <exiftool -s3 -n -f>, @formalTags, $file.Str, :out, :err;
    my $err = $proc.err.slurp(:close);
    my $out = $proc.out.slurp(:close);

    if ($proc.exitcode !== 0) {
        die ImageArchive::Exception::BadExit.new(:err($err));
    }

    my %tags = (@tags Z=> $out.lines).grep({ .value ne '-' });

    # Second run: collect structured values.
    #
    # Now run with -struct so that lists and objects are accounted
    # for. There's no way to know whether a structured tag has been
    # requested or a flattened one, so the strategy is to try both and
    # merge the results.
    #
    # For example, if the desired tag is XMP-iptcExt:SeriesName then
    # using -struct would not return a value. If the tag is XMP-iptcExt:Series,
    # the same would happen if -struct was not used.
    #
    # This distinction is especially important for list tags like
    # XMP-dc:subject. Without -struct, the return value is a comma
    # delimited string. But scalar values could also contain commas.
    $proc = run <exiftool -s3 -n -f -struct>, @formalTags, $file.Str, :out, :err;
    $err = $proc.err.slurp(:close);
    $out = $proc.out.slurp(:close);

    if ($proc.exitcode !== 0) {
        die ImageArchive::Exception::BadExit.new(:err($err));
    }

    my %structTags = (@tags Z=> $out.lines).grep({ .value ne '-' });

    return Hash.new(%tags, %structTags);
}

# Discard the backup copy of a file Exiftool has modified.
#
# Equivalent to exiftool -delete_original! but handled directly.
sub removeOriginal(IO $file) is export {
    my $original = $file.Str ~ "_original";

    if ($original.IO.f) {
        $original.IO.unlink();
    }
}

# Recover the backup copy of a file Exiftool has modified.
#
# Equivalent to exiftool -restore_original but handled directly.
sub restoreOriginal(IO $file) is export {
    my $original = $file.Str ~ "_original";

    if ($original.IO.f) {
        rename($original.IO, $file);
    }
}

# Add tags to a file.
sub tagFile($file, %tags, Bool $dryrun? = False) is export {
    my %aliases = readConfig('aliases');

    my %existingTags = readRawTags($file, %aliases.keys);

    my @commands;

    unless (%existingTags<id>) {
        %tags<id> = generateUuid();
        %tags<datetagged> = DateTime.now();
    }

    unless (%existingTags<avgrgb>) {
        %tags<avgrgb> = getAverageColor($file).join(',');
    }

    unless (%tags) {
        return;
    }

    %tags<modified> = DateTime.now();

    for %tags.kv -> $tag, $value {
        my $formalTag = %aliases{$tag};
        my $existingValue = %existingTags{$tag};

        # This is a cheap way of distinguishing between lists and
        # scalars. No deserialization is performed by readRawTags
        # since it's usually not necessary. This is the exception.
        my $existingValueIsList = ($existingValue or '').starts-with: '[';

        for set($value.list).keys -> $item {
            my $tagValue = $item;
            # If tags were always added in append mode, those that
            # accept scalars would throw a warning. So only append
            # when a tag already exists and accepts a list.
            my $operator = ($existingValueIsList) ?? '+=' !! '=';

            if ($item eq '-') {
                $operator = '=';
                $tagValue = '';
            }

            @commands.push("-{$formalTag}{$operator}{$tagValue}");
        }
    }

    commitTags($file, @commands, $dryrun);
}

# Determine if the provided aliases are valid.
sub testAliases(@aliases) is export {
    my %aliases = readConfig('aliases');
    my $duds = @aliases (-) %aliases.keys;

    if ($duds) {
        die ImageArchive::Exception::BadAlias.new(:offenders($duds));
    }
}

# See if there are contexts with no keywords.
sub testContexts(@contexts) is export {
    my $bag = BagHash.new;

    for @contexts -> $context {
        ($bag{$context}++ if keywordsInContext($context));
    }

    my Set $empties = @contexts (-) $bag.keys;

    if ($empties) {
        die ImageArchive::Exception::EmptyContext.new(:offenders($empties.keys));
    }
}

# See if there are any contexts with no keywords.
sub testContextCoverage(@contexts, @keywords) is export {

    # zipwith meta operator
    # See https://rosettacode.org/wiki/Hash_from_two_arrays#Raku
    my %contexts = @contexts Z=> readConfig('contexts'){@contexts};

    my $bag = BagHash.new;

    for %contexts.kv -> $key, $values {
        my @terms = commaSplit($values);

        ($bag{$key}++ if @terms (&) @keywords or @keywords (&) keywordsInContext($key));
    }

    my Set $empties = @contexts (-) $bag.keys;

    if ($empties.elems > 0) {
        die ImageArchive::Exception::MissingContext.new(
            :allcontexts(readConfig('contexts')),
            :offenders($empties.keys)
        );
    }

}

# Determine if the provided keywords are valid.
sub testKeywords(@keywords) is export {
    my @sections = configSections();
    my %contexts = readConfig('contexts');
    my $duds = @keywords (-) @sections (-) contextNegationKeywords(%contexts);

    if ($duds) {
        die ImageArchive::Exception::BadKeyword.new(:offenders($duds));
    }
}

# Copy tags from one file to another via exiftool, excluding orientation.
sub transferTags(IO $donor, IO $recipient) is export {
    my $donorCreated = readRawTag($donor, 'XMP:CreateDate');
    my $proc = run <exiftool -tagsFromFile>, $donor, '-all:all -x Orientation', "-XMP:CreateDate=$donorCreated", $recipient, :out, :err;

    my $err = $proc.err.slurp(:close);
    my $out = $proc.out.slurp(:close);

    if ($proc.exitcode !== 0) {
        restoreOriginal($recipient);
        die ImageArchive::Exception::BadExit.new(:err($err));
    }

    removeOriginal($recipient);
}

# Remove the tags associated with a keyword.
sub removeKeyword(IO $file, $keyword, Bool $dryrun? = False) is export {
    testKeywords($keyword.list);

    my %aliases = readConfig('aliases');

    my %tags = keywordsToTags($keyword.list);

    my @commands;

    for %tags.kv -> $tag, $values {
        my $formalTag = %aliases{$tag};

        for $values.list -> $item {
            @commands.push("-{$formalTag}-={$item}");
        }
    }

    my $formalTag = %aliases<alias>;
    @commands.push("-{$formalTag}-={$keyword}");

    commitTags($file, @commands, $dryrun);
}

# Remove a tag completely regardless of its value.
multi sub removeAlias(IO $file, Str $alias, Str $value?, Bool $dryrun = False) is export {
    testAliases($alias.list);

    my %aliases = readConfig('aliases');
    my $formalTag = %aliases{$alias};

    my $argument = "-{$formalTag}=";
    if ($value) {
        $argument = "-{$formalTag}-={$value}"
    }

    commitTags($file, $argument.list, $dryrun);
}
