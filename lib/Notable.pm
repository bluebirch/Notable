package Notable;

=head1 NAME

Notable - access the Notable database.

=head1 SYNOPSIS

    use Notable;

    my $notable = Notable->new( $path );

=cut

use Modern::Perl;
use utf8;
use locale;
use open qw(:encoding(UTF-8));
use Notable::Note;
use Carp qw(carp);
use Storable;

#use DateTime::Format::ISO8601;
use File::stat;

our $DEBUG = 0;

=head1 FUNCTIONS

=head2 new( [$data_dir] )

Create a new instance with C<$data_dir> pointing to the Notable data directory.

=cut

sub new {
    my ( $class, @options ) = @_;

    my $data_dir;

    # If there is an odd number of options, assume the first is the path to
    # the Notable data directory.
    if ( scalar @options % 2 == 1 ) {
        $data_dir = shift @options;
    }

    # Bless object
    my $self = bless {}, $class;

    $self->open_dir($data_dir) if ($data_dir);

    return $self;
}

# sub DESTROY {
#     my $self = shift;
#     say STDERR "DESTROY!!";
#     $self->save_cache;
# }

=head2 ok()

Returns true if everything is ok. If not, see C<error()>.

=cut

sub ok {
    my $self = shift;
    return $self->{ok};
}

=head2 error()

Returns error message if not C<ok()>.

=cut

sub error {
    my $self = shift;
    return $self->{error} ? $self->{error} : "";
}

=head2 open_dir( $dir )

Set Notable data directory. Returns true if this is a valid Notable data
directory.

=cut

sub open_dir {
    my $self = shift;
    if (@_) {
        $self->{base_dir}        = File::Spec->rel2abs( File::Spec->canonpath(shift) );
        $self->{notes_dir}       = File::Spec->catdir( $self->{base_dir}, 'notes' );
        $self->{attachments_dir} = File::Spec->catdir( $self->{base_dir}, 'attachments' );
        $self->{config_dir}      = File::Spec->catdir( $self->{base_dir}, '.notable' );
        $self->{cachefile}       = File::Spec->catfile( $self->{config_dir}, "cache.storable" );

    }
    if ( -d $self->{base_dir} && -d $self->{notes_dir} ) {

        # If I'm going to do caching seriously, I need to diff arrays and stuff. See here:
        # https://stackoverflow.com/questions/2933347/difference-of-two-arrays-using-perl

        # Get a list of files with their corresponding mtime
        $self->stat_files;
        $self->read_cache;

        # Determine new and deleted files compared to cache
        my @new_files     = grep { !$self->{cache}->{$_} } keys %{ $self->{files} };
        my @deleted_files = grep { !$self->{files}->{$_} } keys %{ $self->{cache} };

        # Remove deleted files from cache
        foreach my $file (@deleted_files) {
            carp "cache: remove deleted file '$file'" if ($DEBUG);
            delete $self->{cache}->{$file};
        }

        # Check if any cached files need updating
        foreach my $file ( keys %{ $self->{cache} } ) {
            if ( !$self->{cache}->{$file}->{mtime} || $self->{cache}->{$file}->{mtime} != $self->{files}->{$file} ) {
                carp "cache: refresh changed file '$file'" if ($DEBUG);
                $self->{cache}->{$file}->read('header');
                $self->{cache}->{$file}->{mtime} = $self->{files}->{$file};
            }
        }

        # Open new files
        foreach my $file (@new_files) {
            carp "cache: add new file '$file'" if ($DEBUG);
            $self->open_note($file);
            $self->{cache}->{$file}->{mtime} = $self->{files}->{$file};
        }

        $self->{ok} = 1;
    }
    else {
        $self->{ok}    = undef;
        $self->{error} = "Invalid data directory $self->{base_dir}.";
    }
    return $self->{ok};
}

sub close_dir {
    my $self = shift;
    $self->save_cache;
}

sub stat_files {
    my $self = shift;
    opendir my $dir, $self->{notes_dir} or die;    # TODO: error handling
    %{ $self->{files} } = map { $_ => stat( File::Spec->catfile( $self->{notes_dir}, $_ ) )->mtime } grep {m/\.md$/i} readdir $dir;
    closedir $dir;
    return $self->{files};
}

=head2 open_note( $name )

Get note based on file name. Returns a L<Notable::Note> object on success.

=cut

sub open_note {
    my ( $self, $file ) = @_;

    if ( !exists $self->{cache}->{$file} ) {
        carp "open_note( '$file' )" if $DEBUG;
        $self->{cache}->{$file} = Notable::Note->open( file => $file, dir => $self->{notes_dir} );
    }
    return $self->{cache}->{$file};
}

=head1 add_note( title => $title )

Add a new note to the Notable database.

=cut

sub add_note {
    my $self = shift;

    # Create new note, just pass on parameters.
    my $note = Notable::Note->new( dir => $self->{notes_dir}, @_ );

    # If that worked, store the newly created note in the cache and return it.
    if ($note) {
        $self->{cache}->{ $note->file } = $note;
        return $note;
    }
    return undef;
}

# =head2 get_note_title( $title )

# Get note based on title.

# TODO: What about notes with duplicate titles?

# =cut

# sub get_note_title {
#     my ( $self, $title ) = @_;

#     # build title index if needed
#     $self->_build_title_index unless ( $self->{titles} );

#     return $self->{titles}->{$title};
# }

# sub _build_list_of_notebooks {
#     my $self = shift;
#     if ( !exists $self->{notebook} ) {
#         foreach my $file ( @{ $self->{filelist} } ) {
#             my $note = $self->get_note($file);
#             foreach my $notebook ( $note->notebooks ) {
#                 push @{ $self->{notebook}->{$notebook} }, $file;
#             }
#         }
#     }
# }

# sub _build_title_index {
#     my $self = shift;
#     if ( !exists $self->{titles} ) {
#         foreach my $file ( @{ $self->{filelist} } ) {
#             my $note = $self->get_note($file);
#             $self->{titles}->{ $note->title } = $note;    # TODO:-20 check for duplicates
#         }
#     }
# }

=head2 select( $regexp, $tags, $notebooks )

Select notes...

=cut

sub select {
    my $self   = shift;
    my %search = @_;

    # begin with a list of all notes
    my $list = $self->select_all();

    # narrow list to specified notebooks (if specified)
    if ( $search{notebook} ) {
        my @notebooks = ref( $search{notebook} ) ? @{ $search{notebook} } : ( $search{notebook} );
        foreach my $notebook (@notebooks) {
            $list = $self->select_notebook( $notebook, $list );
        }
    }

    # narrow list to specified tags (if specified)
    if ( $search{tag} ) {
        my @tags = ref( $search{tag} ) ? @{ $search{tag} } : ( $search{tag} );
        foreach my $tag (@tags) {
            $list = $self->select_tag( $tag, $list );
        }
    }

    # narrow list to specified title (if specified)
    if ( $search{title} ) {
        $list = $self->select_title( $search{title}, $list );
    }

    # sort list TODO: customizable sort order, maybe I shouldn't sort here at all
    @$list = sort { $a->title cmp $b->title } @$list;

    # return the resulting list of notes
    return wantarray ? @$list : $list;
}

=head2 select_all()

Return a list of all notes.

=cut

sub select_all {
    my $self = shift;

    # if ( !exists $self->{notes} ) {
    #     $self->{notes} = [];
    #     @{ $self->{notes} } = grep {$_} map { $self->open_note($_) } @{ $self->{filelist} }; # TODO: this can silently ignore errors
    # }
    #print Data::Dumper->Dump( [$self->{notes}], [qw(notes)]);
    # something goes wrong here and I don't know why
    my $all = [];
    @$all = grep { !$_->meta('deleted') } map { $self->{cache}->{$_} } sort keys %{ $self->{cache} };

    # foreach my $note (@$all) {
    #     say STDERR "$note->{file}";
    # }
    # say "ABOVE IS FROM select_all() - notes: ", scalar @$all;
    return wantarray ? @$all : $all;
}

=head2 select_tag( $tag[, $list])

Select notes with $tag from $list (an arrayref of L<Notable::Note> objects).

=cut

sub select_tag {
    my ( $self, $tag, $list ) = @_;
    $list = $self->select_all() unless ($list);
    if ($tag) {
        @$list = grep { $_->has_tag($tag) } @$list;
    }
    return wantarray ? @$list : $list;
}

=head2 select_notebook( $notebook[, $list] )

Select notes belonging to $notebook from $list.

=cut

sub select_notebook {
    my ( $self, $notebook, $list ) = @_;
    $list = $self->select_all() unless ($list);
    if ($notebook) {
        @$list = grep { $_->in_notebook($notebook) } @$list;
    }
    return wantarray ? @$list : $list;
}

=head2 select_title( $regexp[, $list ] )

Selecet notes with $regexp in title.

=cut

sub select_title {
    my ( $self, $regex, $list ) = @_;
    $list = $self->select_all() unless ($list);
    if ($regex) {
        carp "select_title: regex=$regex" if ($DEBUG);
        @$list = grep { $_->has('title') && $_->{meta}->{title} =~ m/$regex/i } @$list;
    }
    return wantarray ? @$list : $list;
}

=head2 select_meta( $key, $value[, $list] )

Select notes with metadata $key set to $regex.

=cut

sub select_meta {
    my ( $self, $key, $value, $list ) = @_;
    $list = $self->select_all() unless ($list);
    if ($value) {

        # # a "::" denotes a hierarchial key, like key::subkey
        if ( $key =~ m/->/ ) {
            my ( $mainkey, $subkey ) = split m/->/, $key, 2;

            #print STDERR Data::Dumper->Dump( [ $key, $subkey ], [qw(key subkey)] );
            #say "$_: $_->{path} has $key: ", $_->has($key) foreach (@$list);
            local $_;
            @$list = grep {
                       $_->has($key)
                    && $_->{meta}->{$mainkey}
                    && $_->{meta}->{$mainkey}->{$subkey}
                    && $_->{meta}->{$mainkey}->{$subkey} eq $value
            } @$list;

            #print STDERR Data::Dumper->Dump( [ $list ], [qw(list)] );
        }
        else {
            local ($_);
            @$list = grep { $_->has($key) && $_->{meta}->{$key} eq $value } @$list;

        }
    }

    # foreach my $note (@$list) {
    #     say STDERR "$note->{file}";
    # }
    # say "ABOVE IS FROM select_meta() - notes: ", scalar @$list;
    # die;
    return wantarray ? @$list : $list;
}

=head2 attachments()

Return a list of attachments.

=cut

sub attachments {
    my $self = shift;
    $self->_fetch_list_of_attachments unless ( $self->{attachmentlist} );
    return wantarray ? @{ $self->{attachmentlist} } : $self->{attachmentlist};
}

sub _fetch_list_of_attachments {
    my $self = shift;
    opendir my $dir, $self->{opt}->{attachments_dir} or die;    # TODO: error handling
    $self->{attachmentlist} = [ map { Encode::decode_utf8($_) } readdir $dir ];
    closedir $dir;
}

=head1 linked_attachments

Attachments linked to from a note.

=cut

sub linked_attachments {
    my $self = shift;
    foreach my $note ( $self->select_all ) {
        foreach my $attachment ( $note->attachments ) {
            push @{ $self->{attachments}->{$attachment} }, $note->title;
        }
    }
    return $self->{attachments};
}

sub save_cache {
    my $self = shift;

    # we don't want to cache content, only metadata
    foreach my $note ( values %{ $self->{cache} } ) {
        delete $note->{content};
    }
    carp "cache: write '$self->{cachefile}'" if ($DEBUG);
    store( $self->{cache}, $self->{cachefile} );
}

sub read_cache {
    my $self = shift;
    carp "cache: read '$self->{cachefile}'" if ($DEBUG);
    $self->{cache} = retrieve( $self->{cachefile} ) if ( -f $self->{cachefile} );

    # foreach my $note (values %{$self->{cache}}) {
    #     say STDERR "READ CACHED ", $note->title;
    # }
}

# sub update_metadata {
#     my $self = shift;
#     my $fmt  = DateTime::Format::Strptime->new( pattern => '%FT%T%z', on_error => 'croak' );
#     foreach my $file ( @{ $self->{filelist} } ) {
#         say STDERR "CHECKING FILE $file";
#         if ( my $note = $self->{note}->{$file} ) {
#             $note->verify_metadata;
#         }
#     }
#     die;
# }

sub yamlpp {
    my $self = shift;
    $self->{yamlpp} = YAML::PP->new( footer => 1 ) unless ( $self->{yamlpp} );
    return $self->{yamlpp};
}

1;
