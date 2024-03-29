package Notable::Note;

=head1 NAME

Notable::Note - object oriented interface to a Notable markdown note.

=head1 SYNOPSIS

    use Notable;

    my $notable = Notable->new( $path );
    my $note = $notable->get_note( $filename );

=cut

use Modern::Perl;
use Carp;    # qw(cluck);
use utf8;
use locale;
use open qw(:encoding(UTF-8));
use Encode::Locale;
use Encode;
use YAML::PP qw(Load Dump);
use File::stat;
use File::Spec;
use DateTime;

=head2 Opening and creating notes

=over

=item C<new( parameters )>

Create a new note. Parameters:

=over

=item C<title => $title>

Set title to C<$title>. Title is determined from file name if not specified.

=item C<file => $file>

Set file name to C<$file>. Can be a full path, in which case C<$dir>(below) is
set. File name is determined from title if not specified.

=item C<dir => $dir>

Set directory to <$dir>. Determined from file name if C<$file> is a full path.

=back

Returns a valid L<Notable::Note> object.

=cut

sub new {
    my $class = shift;
    my %opt   = @_;

    # set file name from title if not specified
    if ( !$opt{file} && $opt{title} ) {
        $opt{file} = $opt{title} . '.md';
    }

    # convert file name and path the locale used by the system
    $opt{file} = encode( locale_fs => $opt{file} );
    $opt{dir}  = encode( locale_fs => $opt{dir} ) if ( $opt{dir} );

    # die if we still have no file name
    # TODO:-10 Better error handling in constructor
    die "No file name" unless ( $opt{file} );

    # join dir and file to a full path
    $opt{path} = File::Spec->catfile( $opt{dir}, $opt{file} ) if ( $opt{dir} );

    # convert path to absolute path
    $opt{path} = File::Spec->rel2abs( $opt{path} );

    # separate path and file, keep track of volume
    ( my $vol, $opt{dir}, $opt{file} ) = File::Spec->splitpath( $opt{path} );
    $opt{dir} = File::Spec->catpath( $vol, $opt{dir} );

    # if file exists, we shouldn't make a new object, those should be opened
    # instead
    if ( -f $opt{path} && !$opt{overwrite} ) {
        die "Note $opt{path} already exists";
    }

    # create object
    my $self = bless { file => $opt{file}, dir => $opt{dir}, path => $opt{path}, content => '', meta => {} }, $class;

    # set title if specified
    $self->title( $opt{title} ) if ( $opt{title} );

    # set created and modified time
    $self->created( DateTime->now->iso8601 . 'Z' );
    $self->modified( $self->created );

    return $self;
}

=head2 open( file => $file, dir => $dir )

Open an existing note.

=cut

sub open {
    my $class = shift;
    my %opt   = @_;

    # die if we still have no file name
    # TODO:-10 Better error handling in constructor
    die "No file name" unless ( $opt{file} );

    # join dir and file to a full path
    $opt{path} = $opt{dir} ? File::Spec->catfile( $opt{dir}, $opt{file} ) : File::Spec->canonpath( $opt{file} );

    # convert path to absolute path
    $opt{path} = File::Spec->rel2abs( $opt{path} );

    # separate path and file, keep track of volume
    ( my $vol, $opt{dir}, $opt{file} ) = File::Spec->splitpath( $opt{path} );
    $opt{dir} = File::Spec->catpath( $vol, $opt{dir} );

    # die if file does not exist
    # TODO: better error handling
    if ( !-f $opt{path} ) {
        die "Note $opt{path} does not exist";
    }

    # create object
    my $self = bless { file => $opt{file}, dir => $opt{dir}, path => $opt{path} }, $class;

    # check file mtime
    #$self->{mtime} = stat($self-{path})->mtime;

    # read header
    #$self->read( header_only => 1 );

    return $self;
}

=head2 read( $what )

Read note. Returns true on success. C<$what> is 'header', 'content' or 'both'.
Defaults to 'both'.

=cut

sub read {
    my ( $self, $what ) = @_;

    if ( !$what ) {
        $what = 'both';
    }
    elsif ( $what !~ m/^(?:both|header|content)$/ ) {
        confess "Must specify 'header', 'content' or 'both' ";
    }

    # open file
    my $fh = IO::File->new( $self->{path}, "r" ) || die "Could not open file ($!), do you need to clear the cache?";
    $fh->binmode(":encoding(UTF-8)");

    # read header
    my $header = <$fh>;
    if ( $header !~ m/^---/ ) {    # no YAML header
        $self->{content} = $header;
    }
    else {
        while ( my $line = <$fh> ) {
            if ( $line =~ m/^(?:---|\.\.\.)/ ) {    # end of header
                                                    # This marks the end of the YAML front matter block.
                                                    # Remove the empty line that follows that block.
                my $possible_newline = <$fh>;
                if ( $possible_newline !~ m:^\s*$: ) {
                    $self->{content} = $possible_newline;    # not a newline
                }
                last;
            }
            $header .= $line;
        }
    }

    # read content
    if ( $what eq 'content' || $what eq 'both' ) {
        $self->{content} = '' unless ( exists $self->{content} );
        while ( my $line = <$fh> ) {
            $self->{content} .= $line;
        }
    }

    # # delete content because if header has changed, content probably has too
    # elsif ($what eq 'header' || $what eq 'both') {
    #     delete $self->{content};
    # }

    $fh->close;

    # parse YAML header if it exists and we don't already have metadata
    if ( $what eq 'header' || $what eq 'both' ) {
        $self->{meta} = Load($header) if ($header);
        $self->check_meta;
    }

    #print STDERR Data::Dumper->Dump([$self],[qw(self)]);

    return 1;
}

=head2 write()

Write note to file.

=cut

sub write {
    my $self = shift;

    carp "write: writing '" . $self->file . "'" if ($Notable::DEBUG);

    # we must save the content first because the 'content' method might read
    # the file, meaning it would try to read a file being written...
    my $content = $self->content;

    #print STDERR Data::Dumper->Dump( [$content], [qw(content)]) if ($Notable::DEBUG);

    # open file
    my $fh = IO::File->new( $self->{path}, "w" ) || die "File open fail";
    $fh->binmode(":utf8");

    print $fh Dump( $self->{meta} );
    print $fh "---\n\n";
    print $fh $content if ($content);

    # if ($Notable::DEBUG) {
    #     print STDERR Dump( $self->{meta} );
    #     print STDERR "---\n\n";
    #     print STDERR $content if ($content);
    # }

    $fh->close;

    # update mtime
    $self->{mtime} = stat( $self->{path} )->mtime;
}

=head2 verify_metadata()

Verify that metadata is valid.

=cut

sub check_meta {
    my $self = shift;

    return undef unless ( $self->{meta} );

    # if no title is set, set title from file name
    unless ( $self->has('title') ) {
        my $title = $self->{file};
        $title =~ s/\.md$//i;
        $self->meta( title => $title );
    }

    # if no created date set, set from file stats (if file exists, otherwise
    # use current date)
    unless ( $self->has('created') ) {
        if ( -f $self->{path} ) {
            my $stat = stat( $self->{path} );

            # use mtime, since ctime is something else on many file systems
            $self->meta( created => DateTime->from_epoch( epoch => $stat->mtime )->iso8601 . 'Z' );
        }
        else {
            $self->meta( created => DateTime->now->iso8601 . 'Z' );
        }
    }

    # if no modified date exists, use created date
    unless ( $self->has('modified') ) {
        $self->meta( modified => $self->meta('created') );
    }

    # make sure attachments are unique
    if ( $self->has('attachments') ) {
        my @tmp = do {
            my %seen;
            grep { !$seen{$_}++ } @{ $self->{meta}->{attachments} };
        };
        $self->{meta}->{attachments} = \@tmp;
    }

    # make sure tags are unique
    if ( $self->has('tags') ) {
        my @tmp = do {
            my %seen;
            grep { !$seen{$_}++ } @{ $self->{meta}->{tags} };
        };
        $self->{meta}->{tags} = \@tmp;
    }
}

=head1 meta()

Get and optionally set note metadata.

=cut

sub meta {
    my $self = shift;
    my $key  = shift;

    # read metadata unless we alread have it
    $self->read('header') unless ( $self->{meta} );

    # if no key is specified, return the entire metadata block
    if ( !$key ) {
        return $self->{meta};
    }

    my $retval;

    # a "->" denotes a hierarchial key, like key->subkey
    if ( $key =~ m/->/ ) {
        ( $key, my $subkey ) = split m/->/, $key, 2;
        if (@_) {
            my $val = shift;
            $self->{meta}->{$key}->{$subkey} = $val;
            $self->{mtime} = time;    # modification time stamp
        }
        $retval = $self->{meta}->{$key}->{$subkey} if ( $self->{meta}->{$key} );
    }
    else {
        if (@_) {
            my $val = shift;
            $self->{meta}->{$key} = $val;
            $self->{mtime} = time;    # modification time stamp
        }
        $retval = $self->{meta}->{$key};
    }

    # if the key is an array, return value as array
    # we shouldn't do this: https://lukasatkinson.de/2017/how-to-check-for-an-array-reference-in-perl/
    if ( $retval && ref $retval eq 'ARRAY' ) {
        return wantarray ? @{$retval} : $retval;
    }

    # return value of key
    return $retval;
}

=head2 delete_meta( $key )

Delete metadata key.

=cut

sub delete_meta {
    my $self = shift;
    my $key  = shift;

    return undef unless ($key);

    # read metadata unless we alread have it
    $self->read('header') unless ( $self->{meta} );

    # a "->" denotes a hierarchial key, like key->subkey
    if ( $key =~ m/->/ ) {
        ( $key, my $subkey ) = split m/->/, $key, 2;
        if ( defined $self->{meta}->{$key}->{$subkey} ) {
            delete $self->{meta}->{$key}->{$subkey};
            $self->{mtime} = time;    # modification time stamp
            return 1;
        }
    }
    elsif ( defined $self->{meta}->{$key} ) {
        delete $self->{meta}->{$key};
        $self->{mtime} = time;        # modification time stamp
        return 1;
    }

    return undef;
}

=head1 has( $key )

Returns true if $key exists in the note metadata.

=cut

sub has {
    my ( $self, $key ) = @_;

    # read metadata unless we alread have it
    $self->read('header') unless ( $self->{meta} );

    # a "->" denotes a hierarchial key, like key->subkey
    if ( $key =~ m/->/ ) {
        ( $key, my $subkey ) = split m/->/, $key, 2;

        #print STDERR "in has(): ", Data::Dumper->Dump([$key, $subkey],[qw(key subkey)]);
        return $self->{meta}->{$key} && $self->{meta}->{$key}->{$subkey} ? 1 : 0;
    }
    else {
        #print STDERR "in has(): ", Data::Dumper->Dump([$self, $key],[qw(self key)]);
        return $self->{meta}->{$key} ? 1 : 0;
    }
}

=head title( $title )

Get (or set) title.

=cut

sub title {
    my $self = shift;
    return $self->meta( 'title', @_ );
}

=head2 tags()

Get tags. Ignores Notebooks tags.

=cut

sub tags {
    my $self = shift;
    my @tags;
    if ( $self->has('tags') ) {
        @tags = grep { !s:^Notebooks/:: } $self->meta('tags');
    }
    return wantarray ? @tags : \@tags;
}

=head2 has_tag( $tag )

Returns true if note has current tag.

=cut

sub has_tag {
    my ( $self, $tag ) = @_;
    my %tag = map { $_ => 1 } $self->tags;
    return $tag{$tag};
}

=head2 add_tags( @tags )

Add tags to note.

=cut

sub add_tags {
    my $self = shift;
    foreach my $tag (@_) {
        if ( !grep m/^\Q$tag\E$/, @{ $self->{meta}->{tags} } ) {
            push @{ $self->{meta}->{tags} }, $tag;
            say "add_tags: add tag '$tag'" if ($Notable::DEBUG);
        }
    }
    $self->{mtime} = time;    # modification time stamp

}

=head2 remove_tags( @tags )

Remove tags from note.

=cut

sub remove_tags {
    my $self = shift;
    if ( $self->has('tags') ) {
        foreach my $tag (@_) {
            next unless $tag;
            @{ $self->{meta}->{tags} } = grep { !m/^\Q$tag\E$/ } @{ $self->{meta}->{tags} };
        }
    }
    $self->{mtime} = time;    # modification time stamp

}

=head2 notebooks()

Returns which notebooks (if any) the note belongs to.

=cut

sub notebooks {
    my $self = shift;
    my @notebooks;
    if ( $self->has('tags') ) {
        @notebooks = grep {s:^Notebooks/::} $self->meta('tags');
    }
    return wantarray ? @notebooks : \@notebooks;
}

=head2 in_notebook( $notebook )

Returns true if note belongs to $notebook.

=cut

sub in_notebook {
    my ( $self, $notebook ) = @_;
    my %notebook = map { $_ => 1 } $self->notebooks;
    return $notebook{$notebook};
}

=head2 created( $iso8601_timestamp )

Get (or set) created time.

=cut

sub created {
    my $self = shift;
    return $self->meta( 'created', @_ );
}

=head2 created_ymd()

Get the created date in YYYY-MM-DD format.

=cut

sub created_ymd {
    my $self = shift;
    my $date = $self->created;
    $date =~ s/T.*//;
    return $date;
}

=head2 modified( $iso8601_timestamp )

Get (or set) modification time.

=cut

sub modified {
    my $self = shift;
    return $self->meta( 'modified', @_ );
}

=head2 modified_ymd()

Get the modified date in YYYY-MM-DD format.

=cut

sub modified_ymd {
    my $self = shift;
    my $date = $self->modified;
    $date =~ s/T.*//;
    return $date;
}

=head2 modified_now()

Update the modified metadata with the current time.

=cut

sub modified_now {
    my $self = shift;
    $self->modified( DateTime->now->iso8601 . 'Z' );
}

=head2 deleted()

Returns true if the note is deleted, false otherwise.

=cut

sub deleted {
    my $self = shift;
    return $self->has('deleted') && $self->meta('deleted');
}

=head2 archived()

Returns true if the note is archived, false otherwise.

=cut

sub archived {
    my $self = shift;
    return $self->has('archived') && $self->meta('archived');
}

=head active()

Returns true if the note is neither archived nor deleted.

=cut

sub active {
    my $self = shift;
    return !$self->archived && !$self->deleted;
}

sub file {
    my $self = shift;
    return $self->{file};
}

sub filename {
    my $self = shift;
    return $self->{file};
}

=head2 attachments()

Return list of attachments.

=cut

sub attachments {
    my $self        = shift;
    my $attachments = $self->meta('attachments');
    $attachments = [] unless ($attachments);
    return wantarray ? @$attachments : $attachments;
}

=head2 add_attachments( @file_names )

Add tags to note.

=cut

sub add_attachments {
    my $self = shift;
    foreach my $attachment (@_) {
        if ( !grep m/^\Q$attachment\E$/, @{ $self->{meta}->{attachments} } ) {
            push @{ $self->{meta}->{attachments} }, $attachment;
        }
    }
}

=head2 content( $content )

Get or set the content. This should be valid markdown.

=cut

sub content {
    my $self = shift;
    # print STDERR Data::Dumper->Dump( [$self], [qw(self)]);
    # carp "that's self";
    # if (-f $self->{path}) {
    #     say STDERR "FILE EXISTS: $self->{path}";
    # }
    # else {
    #     say STDERR "FILE DOESN'T EXIST: $self->{path}";
    # }
    if (@_) {
        $self->{content} = shift;
        $self->{mtime}   = time;    # modification time stamp
    }

    # if content has not yet been read from file, do it
    elsif ( !defined $self->{content} && -f $self->{path} ) {
        $self->read('content');
    }

    return $self->{content};
}

sub one_line {
    my $self      = shift;
    my $s         = $self->title;
    my @notebooks = $self->notebooks;
    if (@notebooks) {
        $s .= " (" . join( ", ", @notebooks ) . ")";
    }
    return $s;
}

sub dump {
    my $self = shift;
    my $s    = "===\n";
    $s .= "Title:        " . $self->title . "\n";
    $s .= "File:         " . $self->file . "\n";
    $s .= "Tags:         " . join( "\n              ", $self->tags, ) . "\n";
    $s .= "Attachments:  " . join( "\n              ", $self->attachments, ) . "\n";
    $s .= "---\n";
    $s .= $self->content;
    return $s;
}

sub existing_attachments {
    my $self     = shift;
    my @existing = grep -f $self->{opt}->{attachments_dir} . $_, $self->attachments;
    return wantarray ? @existing : \@existing;
}

sub missing_attachments {
    my $self    = shift;
    my @missing = grep !-f $self->{opt}->{attachments_dir} . $_, $self->attachments;
    return wantarray ? @missing : \@missing;

}

sub links {
    my $self    = shift;
    my $content = $self->content;
    my @links   = ( $content =~ m:\[.*?\]\((.*?)\):g );
    return wantarray ? @links : \@links;
}

sub linked_attachments {
    my $self  = shift;
    my @links = grep s:^\@attachment/::, $self->links;
    return wantarray ? @links : \@links;
}

1;
