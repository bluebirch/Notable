package Notable;

=head1 NAME

Notable - access the Notable database.

=head1 SYNOPSIS

    use Notable;
    my $notable = Notable->new();

    # Open a Notable directory.
    $notable->open_dir( "$ENV{HOME}/.notable" );

    # Select all notes in a specific notebook.
    my @notes = $notable->select( notebook => "Notebook" );

    # Loop over notes with specific tag and word in title.
    foreach my $note ($notable->select( tag => "Tag1", title => "A test" ) ) {
        say $note->title;
    }

    # Close Notable directory (needed to save cache).
    $notable->close_dir;

=head1 DESCRIPTION

The C<Notable.pm> module is a Perl interface to a
L<Notable|https://notable.app> database. It's intended for easy scripting and
manipulation of Notable notes.

=cut

use Modern::Perl;
use utf8;
use locale;
use open qw(:encoding(UTF-8));
use Notable::Note;
use Carp qw(carp);
use Storable;
use File::stat;

our $DEBUG = 1;

=head1 FUNCTIONS

=head2 Selecting a Notable data directory

=over

=item C<new( [data_dir] )>

Create a new C<Notable> instance. If C<data_dir> dir is supplied, open_dir is
automatically called.

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

=item C<open_dir( dir )>

Set Notable data directory to C<dir>. Returns true if a valid Notable data
directory is found.

    $success = $notable->open_dir( "$ENV{HOME}/Notable" );
    # foo

Why isn't this regarded as Perl code?

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
        $self->_stat_files;
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


sub _stat_files {
    my $self = shift;
    carp "stat files $self->{notes_dir}" if ($DEBUG);
    #my $glob = File::Spec->catfile( $self->{notes_dir}, "*" );
    #print "glob=$glob";
    #my @files = glob $glob;
    opendir my $dir, $self->{notes_dir} or die;    # TODO: error handling
    #my @files = readdir $dir;
    #print Data::Dumper->Dump( [\@files], [qw(@files)] );
    %{ $self->{files} } = map { $_ => stat( File::Spec->catfile( $self->{notes_dir}, $_ ) )->mtime } grep {m/\.md$/i} readdir $dir;
    closedir $dir;
    #die;
    return $self->{files};
}


=item close_dir

Close Notable data directory. This is necessary if caching is used.

=cut

sub close_dir {
    my $self = shift;
    $self->save_cache;
}

=back

=head2 Selecting notes

=over

=item C<select( search_parameters )>

Select notes based on tags, notebooks and/or title. The following parameters
can be specified:

=over

=item title => $title

Find notes with title matching the regex C<$title>. Example:

    @notes = $notable->select( title => "words.*in.*title" );

=item tag => $tag

Find notes matching tag C<$tag>. If C<$tag> is a reference to an array, all
tags will be matched using the logical B<and> operator. Examples:

    @notes = $notable->select( tag => "Tag" );
    @notes = $notable->select( tag => [ "Tag1", "Tag2", "Tag3" ] );

=back

=cut

sub select {
    my $self   = shift;
    my %search = @_;

    say STDERR "select!";

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

=item C<select_all()>

Return an array all active notes as L<Notable::Note> objects, that is, all notes that are neither deleted nor archived.

=cut

sub select_all {
    my $self = shift;
    my $all = [];
    @$all = grep { $_->active } map { $self->{cache}->{$_} } sort keys %{ $self->{cache} };
    return wantarray ? @$all : $all;
}

=item C<select_tag( $tag, $list )>

Select notes from C<$list> (an arrayref of L<Notable::Note> objects) that has tag C<$tag>. If C<$list> is omitted, C<select_all()> is used.

=cut

sub select_tag {
    my ( $self, $tag, $list ) = @_;
    $list = $self->select_all() unless ($list);
    if ($tag) {
        @$list = grep { $_->has_tag($tag) } @$list;
    }
    return wantarray ? @$list : $list;
}

=item C<select_notebook( $notebook, $list )>

Select notes from C<$list> that belongs to notebook C<$notebook>. If C<$list> is omitted, C<select_all()> is used.

=cut

sub select_notebook {
    my ( $self, $notebook, $list ) = @_;
    $list = $self->select_all() unless ($list);
    if ($notebook) {
        @$list = grep { $_->in_notebook($notebook) } @$list;
    }
    return wantarray ? @$list : $list;
}

=item C<select_title( $regex, $list )>

Select notes from C<$list> where C<$regex> matches the title. If C<$list> is omitted, C<select_all()> is used.

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

=item C<select_meta( $key, $value, $list )>

Select notes from C<$list> where metadata C<$key> matches C<$value>. If C<$list> is omitted, C<select_all()> is used.

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

=item C<select_has( $key, $list )>

Select notes from C<$list> that has existing metadata C<$key>. If C<$list> is omitted, C<select_all()> is used.

=cut

sub select_has {
    my ( $self, $key, $list ) = @_;
    $list = $self->select_all() unless ($list);
    local ($_);
    @$list = grep { $_->has($key) } @$list;
    return wantarray ? @$list : $list;
}

=head2 Opening and adding individual notes

=over

=item open_note( filename )

Get note with specified file name. Returns a L<Notable::Note> object on success.

=cut

sub open_note {
    my ( $self, $file ) = @_;

    if ( !exists $self->{cache}->{$file} ) {
        carp "open_note( '$file' )" if $DEBUG;
        $self->{cache}->{$file} = Notable::Note->open( file => $file, dir => $self->{notes_dir} );
    }
    return $self->{cache}->{$file};
}

=item add_note( title => $title )

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

=back

=head2 Attachments

=over

=item C<attachments>

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

=item C<linked_attachments>

Return a list of linked attachments, that is, attachments that are actually attached to a note.

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

=back

=head2 Caching

C<Notable.pm> use caching with L<Storable>. The cache is saved as
C<storable.cache> in the C<.notable> subdirectory of the Notable data
directory.

=over

=item C<read_cache>

Read cache.

=cut

sub read_cache {
    my $self = shift;
    carp "cache: read '$self->{cachefile}'" if ($DEBUG);
    $self->{cache} = retrieve( $self->{cachefile} ) if ( -f $self->{cachefile} );
}

=item C<save_cache>

Save cache.

=back

=cut

sub save_cache {
    my $self = shift;

    # we don't want to cache content, only metadata
    foreach my $note ( values %{ $self->{cache} } ) {
        delete $note->{content};
    }
    carp "cache: write '$self->{cachefile}'" if ($DEBUG);
    store( $self->{cache}, $self->{cachefile} );
}

=back

=head2 Error handling

=over

=item ok

Returns true if everything is ok. If not, see C<error>.

=cut

sub ok {
    my $self = shift;
    return $self->{ok};
}

=item error

Returns error message if not C<ok()>.

=cut

sub error {
    my $self = shift;
    return $self->{error} ? $self->{error} : "";
}

1;
