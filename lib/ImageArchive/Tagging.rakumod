unit module ImageArchive::Tagging;

use ImageArchive::Color;
use ImageArchive::Config;
use ImageArchive::Exception;
use ImageArchive::Util;

# Prompt for tag values that are unique to the image.
sub askQuestions() is export {
    my %prompts = readConfig('prompts');

    my %answers;

    for %prompts.sort(*.key) {
        my $answer = prompt "{$_.value}: ";
        $answer .= trim;
        next unless $answer;
        %answers{$_.key} = ($_.trim for $answer.split(','))
    }

    return %answers;
}

# Write one or more tags to a file via exiftool.
sub commitTags(IO $file, @commands, Bool $dryRun? = False) is export {
    if ($dryRun) {
        wouldHaveDone("exiftool -ignoreMinorErrors {@commands} {$file}");
        return;
    }

    my $proc = run <exiftool -ignoreMinorErrors>, @commands, $file.Str, :out, :err;

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

# Extract multiple tags from a file.
sub readRawTags(IO $file, @tags, Str $flags = '') is export {
    my %aliases = readConfig('aliases');
    my @formalTags;
    for @tags -> $tag {
        @formalTags.push('-' ~ (%aliases{$tag} || $tag));
    }

    my $proc = run qqw{exiftool -s3 -n -struct -f $flags}, @formalTags, $file.Str, :out, :err;
    my $err = $proc.err.slurp(:close);
    my $out = $proc.out.slurp(:close);

    if ($proc.exitcode !== 0) {
        die ImageArchive::Exception::BadExit.new(:err($err));
    }

    my %tags = @tags Z=> $out.lines;
    return %tags.grep({ .value ne '-' });
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
sub tagFile($file, %tags, Bool $dryRun? = False) is export {
    my %aliases = readConfig('aliases');

    my %existingTags = readRawTags($file, %aliases.keys);

    my @commands;

    unless (%existingTags<id>) {
        %tags<id> = generateUuid();
        %tags<datetagged> = DateTime.now();
    }

    unless (%existingTags<relation>) {
        %tags<relation> = sprintf(
            'average-color:srgb(%s)',
            getAverageColor($file).join(',')
        );
    }

    %tags<modified> = DateTime.now();

    for %tags.kv -> $tag, $value {
        my $formalTag = %aliases{$tag};
        my $existingValue = %existingTags{$tag};

        # This is a cheap way of distinguishing between list tags and
        # scalar tags. No deserialization is performed by readRawTags
        # since it's usually not necessary. This is the exception.
        my $existingValueIsList = $existingValue && $existingValue.starts-with: '[';

        for set($value.list).keys -> $item {
            # If tags were always added in append mode, those that
            # accept scalars would throw a warning. So only append
            # when a tag already exists and accepts a list.
            my $operator = ($existingValueIsList) ?? '+=' !! '=';
            @commands.push("-{$formalTag}{$operator}{$item}");
        }
    }

    commitTags($file, @commands, $dryRun);
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

# Copy tags from one file to another via exiftool.
sub transferTags(IO $donor, IO $recipient) is export {
    my $proc = run <exiftool -tagsFromFile>, $donor, $recipient, :out, :err;

    my $err = $proc.err.slurp(:close);
    my $out = $proc.out.slurp(:close);

    if ($proc.exitcode !== 0) {
        restoreOriginal($recipient);
        die ImageArchive::Exception::BadExit.new(:err($err));
    }

    removeOriginal($recipient);
}

# Remove the tags associated with a keyword.
sub untagKeyword(IO $file, $keyword, Bool $dryRun? = False) is export {
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

    commitTags($file, @commands, $dryRun);
}

# Remove a tag completely regargless of its value.
multi sub untagAlias(IO $file, Str $alias, Bool $dryRun = False) is export {
    testAliases($alias.list);

    my %aliases = readConfig('aliases');
    my $formalTag = %aliases{$alias};

    commitTags($file, "-{$formalTag}=".list, $dryRun);

}

# Remove a value from a tag.
multi sub untagAlias(IO $file, Str $alias, Str $value, Bool $dryRun = False) is export {
    testAliases($alias.list);

    my %aliases = readConfig('aliases');

    my $formalTag = %aliases{$alias};

    commitTags($file, "-{$formalTag}-={$value}".list, $dryRun);
}
