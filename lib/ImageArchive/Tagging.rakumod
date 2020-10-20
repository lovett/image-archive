unit module ImageArchive::Tagging;

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
sub readTag(IO $file, $tag) is export {
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
sub readTags(IO $file, @tags, Str $flags = '') is export {
    my %aliases = readConfig('aliases');
    my @formalTags;
    for @tags -> $tag {
        @formalTags.push('-' ~ (%aliases{$tag} || $tag));
    }

    my $proc = run qqw{exiftool -args $flags}, @formalTags, $file.Str, :out, :err;
    my $err = $proc.err.slurp(:close);
    my $out = $proc.out.slurp(:close);

    if ($proc.exitcode !== 0) {
        die ImageArchive::Exception::BadExit.new(:err($err));
    }

    my %tags;
    for $out.lines -> $line {
        my @pairs = $line.split('=');

        my $alias = tagToAlias(@pairs.first.substr(1));

        %tags{$alias} = @pairs[1];
    }

    return %tags;
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

# Apply one or more tags specified as keywords to a file.
sub tagFile($file, %tags, @keywords?, Bool $dryRun? = False) is export {

    my $uuid = readTag($file, 'id');

    unless ($uuid) {
        %tags<id> = generateUuid();
    }

    # Storing the aliases makes it possible to locate images based on
    # how they were tagged (as opposed to what they were tagged with).
    if (@keywords) {
        %tags<alias> = set(readTag($file.IO, 'alias').Array.append(@keywords.sort));
    }

    %tags<datetagged> = DateTime.now();

    my @commands = tagsToExifTool(%tags);

    commitTags($file, @commands, $dryRun);
}

# Convert a set of tag keywords to a list of arguments suitable for exiftool.
sub tagsToExifTool(%tags) is export {
    my %aliases = readConfig('aliases');

    my @commands;

    for %tags.keys -> $tag {
        my $formalTag = %aliases{$tag};

        my $value = %tags{$tag};

        if ($value ~~ List) {
            for $value.list -> $item {
                my $operator = ($item ~~ $value.first) ?? "=" !! "+=";
                @commands.push("-{$formalTag}{$operator}{$item}");
            }
        } elsif ($value ~~ Str && $value.starts-with('-')) {
            @commands.push("-{$formalTag}-={$value.substr(1)}");
        } else {
            @commands.push("-{$formalTag}={$value}");
        }
    }

    return @commands;
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

# Remove the tags of one or more keywords from a file.
sub untagKeywords(IO $file, @keywords, Bool $dryRun? = False) is export {
    testKeywords(@keywords);

    my %tags = keywordsToTags(@keywords);

    for %tags.kv -> $tag, $value {
        %tags{$tag} = "-" ~ $value;
    }

    my $aliases = readTag($file.IO, 'alias');
    %tags<alias> = commaSplit($aliases) (-) @keywords;

    my @commands = tagsToExifTool(%tags);

    commitTags($file, @commands, $dryRun);
}
