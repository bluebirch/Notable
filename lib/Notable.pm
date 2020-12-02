package Notable;

=head1 NAME

Notable - access the Notable database.

=head1 SYNOPSIS

    use Notable;

    my $notable = Notable->new( $path );

=cut

use strict;
use warnings;
use utf8;
use locale;
use open qw(:encoding(UTF-8) :std);
use Notable::Note;
use Data::Dumper;
use Carp;

=head1 FUNCTIONS

=head2 new( [$data_dir] )

Create a new instance with C<$data_dir> pointing to the Notable data directory.

=cut

sub new {
    my ( $class, @options ) = @_;

    my $data_dir = $ENV{HOME} . '.notable';    # default path

    # If there is an odd number of options, assume the first is the path to
    # the Notable data directory.
    if ( scalar @options % 2 == 1 ) {
        $data_dir = shift @options;
    }

    # Bless object
    my $self = bless { opt => {} }, $class;

    # Verify data directory and get list of files
    if ( $self->_verify_data_dir($data_dir) ) {
        $self->_fetch_list_of_files;
    }

    return $self;
}

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

# Verify the Notable data directory.
sub _verify_data_dir {
    my $self = shift;
    if (@_) {
        $self->{opt}->{base_dir} = shift;
        $self->{opt}->{base_dir} .= '/' unless ( $self->{opt}->{base_dir} =~ m:/$: );
        $self->{opt}->{notes_dir}       = $self->{opt}->{base_dir} . 'notes/';
        $self->{opt}->{attachments_dir} = $self->{opt}->{base_dir} . 'attachments/';
    }
    if ( -d $self->{opt}->{base_dir} && -d $self->{opt}->{notes_dir} ) {
        $self->{ok} = 1;
    }
    else {
        $self->{ok}    = undef;
        $self->{error} = "Invalid data directory $self->{opt}->{base_dir}.";
    }
    return $self->{ok};
}

sub _fetch_list_of_files {
    my $self = shift;
    opendir my $dir, $self->{opt}->{notes_dir} or die;    # TODO: error handling
    $self->{filelist} = [ grep {m/\.md$/i} map { Encode::decode_utf8($_) } readdir $dir ];

    #print STDERR Dumper $self->{filelist};
    #confess;
    closedir $dir;
}

=head2 get_note( $name )

Get note based on file name. Returns a L<Notable::Note> object on success.

=cut

sub get_note {
    my ( $self, $file ) = @_;
    if ( !exists $self->{note}->{$file} ) {
        $self->{note}->{$file} = Notable::Note->new( $file, $self->{opt} );
    }
    return $self->{note}->{$file};
}

=head2 get_note_title( $title )

Get note based on title.

TODO: What about notes with duplicate titles?

=cut

sub get_note_title {
    my ( $self, $title ) = @_;

    # build title index if needed
    $self->_build_title_index unless ( $self->{titles} );

    return $self->{titles}->{$title};
}

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
#             $self->{titles}->{ $note->title } = $note;    # TODO: check for duplicates
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
            print STDERR "searching notebook $notebook\n";
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
    if ( !exists $self->{notes} ) {
        $self->{notes} = [];
        @{ $self->{notes} } = grep {$_} map { $self->get_note($_) } @{ $self->{filelist} };  # TODO: this can silently ignore errors
    }
    return wantarray ? @{ $self->{notes} } : $self->{notes};
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
    my ( $self, $regexp, $list ) = @_;
    $list = $self->select_all() unless ($list);
    if ($regexp) {
        my $re = qr/$regexp/i;
        @$list = grep { $_->{props}->{title} =~ m/$re/ } @$list;
    }
    return wantarray ? @$list : $list;
}

=head2 attachments()

Return a list of attachments.

=cut

sub attachments {
    my $self = shift;
    $self->_fetch_list_of_attachments unless ( $self->{attachmentlist} );
    print Dumper $self->{attachmentlist};
    return wantarray ? @{ $self->{attachmentlist} } : $self->{attachmentlist};
}

sub _fetch_list_of_attachments {
    my $self = shift;
    print STDERR "opendir $self->{opt}->{attachments_dir}\n";
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

1;
