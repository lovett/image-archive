unit module ImageArchive::Exception;

use ImageArchive::Config;

# A search with an invalid filter.
class ImageArchive::Exception::BadFilter is Exception is export {
    method message {
        "Unknown search filter."
    }
}

# An unknown alias is used.
class ImageArchive::Exception::BadAlias is Exception is export {
    has Set $.offenders;
    method message {
        my $label = ($!offenders.elems == 1) ?? "alias" !! "aliases";
        "Unknown {$label}: {$!offenders.keys.join(', ')}";
    }
}

# An unknown keyword is used during tagging.
class ImageArchive::Exception::BadKeyword is Exception is export {
    has Set $.offenders;
    method message {
        my $label = ($!offenders.elems == 1) ?? "keyword" !! "keywords";
        "Unknown {$label}: {$!offenders.keys.join(', ')}";
    }
}

# A tagging context without keywords.
class ImageArchive::Exception::EmptyContext is Exception is export {
    has Seq $.offenders;
    method message {
        my $label = ($!offenders.elems == 1) ?? "context has" !! "contexts have";
        "The following {$label} no keywords: {$!offenders.join(', ')}";
    }
}

# An external call did not exit cleanly.
class ImageArchive::Exception::BadExit is Exception is export {
    has Str $.err;

    method message {
        $!err;
    }
}

# A file slated for import clashes with an existing file.
class ImageArchive::Exception::FileExists is Exception is export {
    has IO $.path;
    method message {
        "Filename clashes with {$!path}";
    }
}

# A path slated for deport clases with an existing path.
class ImageArchive::Exception::DeportConflict is Exception is export {
    has IO::Path $.path;
    method message {
        "{$!path} already exists";
    }
}

# The configuration is missing an expected value.
class ImageArchive::Exception::MissingConfig is Exception is export {
    has Str $.key;

    method message {
        "Cannot continue. No {$!key} in configuration file.";
    }
}

# A tagging context is not accounted for.
class ImageArchive::Exception::MissingContext is Exception is export {
    has Seq $.offenders;
    method message {
        my $label = ($!offenders.elems == 1) ?? "context" !! "contexts";
        "Keywords are missing for {$!offenders.elems} {$label}: {$!offenders.join(', ')}";
    }

}

# The search command is invoked without search terms.
class ImageArchive::Exception::NoSearchQuery is Exception is export {
    method message {
        "No search terms provided."
    }
}

# A file thought to be in the archive does not exist.
class ImageArchive::Exception::PathNotFoundInArchive is Exception is export {
    method message {
        "No such path in archive.";
    }
}

# A file is not within a workspace.
class ImageArchive::Exception::PathNotFoundInWorkspace is Exception is export {
    method message {
        "File is not within a workspace.";
    }
}

# A UUID cannot be generated using OS-provided mechanisms.
class ImageArchive::Exception::UUID is Exception is export {
    method message {
        "Unable to generate a unique id.";
    }
}
