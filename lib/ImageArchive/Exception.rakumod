unit module ImageArchive::Exception;

# A parent class for inheriting backtrace suppression.
class ImageArchive::Exception is Exception {
    multi method gist {
        $.message;
    }
}

# An unknown alias is used.
class ImageArchive::Exception::BadAlias is ImageArchive::Exception is export {
    has Set $.offenders;

    method message {
        my $label = ($!offenders.elems == 1) ?? "alias" !! "aliases";
        "Unknown {$label}: {$!offenders.keys.join(', ')}";
    }
}

# An unknown keyword is used during tagging.
class ImageArchive::Exception::BadKeyword is ImageArchive::Exception is export {
    has Set $.offenders;

    method message {
        my $label = ($!offenders.elems == 1) ?? "keyword" !! "keywords";
        "Unknown {$label}: {$!offenders.keys.join(', ')}";
    }
}

# A tagging context without keywords.
class ImageArchive::Exception::EmptyContext is ImageArchive::Exception is export {
    has Seq $.offenders;
    method message {
        my $label = ($!offenders.elems == 1) ?? "context has" !! "contexts have";
        "The following {$label} no keywords: {$!offenders.join(', ')}";
    }
}

# An external call did not exit cleanly.
class ImageArchive::Exception::BadExit is ImageArchive::Exception is export {
    has Str $.err;

    method message {
        $!err;
    }
}

# A path already exists.
class ImageArchive::Exception::PathConflict is ImageArchive::Exception is export {
    has IO::Path $.path;
    has Str $.reason;

    method message {
        given $!reason {
            when "basename" {
                "File name clashes with {$!path}";
            }

            default {
                "{$!path} already exists";
            }
        }
    }
}

# The configuration is missing an expected value.
class ImageArchive::Exception::MissingConfig is ImageArchive::Exception is export {
    has Str $.key;
    has Str $.config;

    method message {
        "Cannot proceed. Missing \"{$!key}\" in {$!config}";
    }
}

# A tagging context is not accounted for.
class ImageArchive::Exception::MissingContext is ImageArchive::Exception is export {
    has Seq $.offenders;

    method message {
        my $label = ($!offenders.elems == 1) ?? "context" !! "contexts";
        "Keywords are missing for {$!offenders.elems} {$label}: {$!offenders.join(', ')}";
    }

}

# A path expected to be a workspace is not.
class ImageArchive::Exception::NotAWorkspace is ImageArchive::Exception is export {

    method message {
        "Path is not a workspace.";
    }
}

# A workspace cannot be paired with a master file.
class ImageArchive::Exception::OrphanedWorkspace is ImageArchive::Exception is export {
    has IO::Path $.path;

    method message {
        "Could not find a master file for " ~ $!path;
    }
}

# A file or directory thought to be in the archive does not exist.
class ImageArchive::Exception::PathNotFoundInArchive is ImageArchive::Exception is export {
    has IO::Path $.path;

    method message {
        my $message = "Path not found in archive";
        $message ~= ($!path) ?? ": $!path" !! '.';
        return $message;
    }
}

# A file thought to be in a workspace does not exist.
class ImageArchive::Exception::PathNotFoundInWorkspace is ImageArchive::Exception is export {
    has IO::Path $.path;

    method message {
        my $message = "File not found in workspace";
        $message ~= ($!path) ?? ": $!path" !! '.';
        return $message;
    }
}

# A UUID cannot be generated using OS-provided mechanisms.
class ImageArchive::Exception::UUID is ImageArchive::Exception is export {

    method message {
        "Unable to generate a unique id.";
    }
}

# The current shell is not supported.
class ImageArchive::Exception::UnsupportedShell is ImageArchive::Exception is export {

    method message {
        "Sorry, support for for {%*ENV<SHELL>} is not available.";
    }
}
