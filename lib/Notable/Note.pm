package Notable::Note;

=head1 NAME

Notable::Note - object oriented interface to Notable markdown notes.

=head1 SYNOPSIS

    use Notable;

    my $notable = Notable->new( $path );
    my $note = $notable->get_note( $filename );

=cut

use strict;
use warnings;
use utf8;
use locale;
use open qw(:encoding(UTF-8) :std);
use Encode;
use IO::File;
use File::stat;
use YAML::XS;
use DateTime;
use DateTime::Format::ISO8601;

#use DateTime::Format::ISO8601::Format;
use Data::Dumper;

sub new {
    my ( $class, $file, $opt ) = @_;

    # Make sure there at least an empty path
    $opt->{notes_dir} = "" unless ( $opt->{notes_dir} );

    # If file exists, return new object
    if ( -f $opt->{notes_dir} . $file ) {
        my $self = bless { file => $file, opt => $opt }, $class;
        $self->_get_yaml_header;
        $self->_verify_properties;
        return $self;
    }

    # Refuse to create an object if the file does not exist (this is stupid,
    # create new file instead)
    else {
        return undef;
    }
}

sub _get_yaml_header {
    my $self = shift;

    # read header if we haven't done that yet
    if ( !$self->{header} ) {
        $self->_get_content(1);
    }

    # parse YAML if we have a header
    if ( $self->{header} ) {
        $self->{props} = Load( encode( "UTF-8", $self->{header} ) );
    }
    return $self->{header};
}

sub _verify_properties {
    my $self = shift;

    # if no title is set, set title from file name
    unless ( $self->has('title') ) {
        my $title = $self->{file};
        $title =~ s/\.md$//i;
        $self->property( 'title', $title );
    }

    # if no created date set, set from file stats
    unless ( $self->has('created') ) {
        my $stat = stat( $self->{opt}->{notes_dir} . $self->{file} );

        # use mtime, since ctime is something else on many file systems
        $self->{created} = DateTime->from_epoch( epoch => $stat->mtime );
        $self->{props}->{created} = $self->{created}->iso8601 . 'Z';
    }

    # if no modified date exists, use created date
    unless ( $self->has('modified') ) {
        $self->{modified} = $self->created;
        $self->{props}->{modified} = $self->{modified}->iso8601 . 'Z';
    }
}

sub property {
    my $self     = shift;
    my $property = shift;
    $self->_get_yaml_header unless ( $self->{props} );
    if (@_) {
        $self->{props}->{$property} = shift;
        $self->_modified_now;
    }
    if ( exists $self->{props}->{$property} && ref $self->{props}->{$property} eq 'ARRAY' )
    {    # we shouldn't do this: https://lukasatkinson.de/2017/how-to-check-for-an-array-reference-in-perl/
        return wantarray ? @{ $self->{props}->{$property} } : $self->{props}->{$property};
    }
    return $self->{props}->{$property};
}

sub properties {
    my $self = shift;
    $self->_get_yaml_header unless ( $self->{props} );
    my $props = { %{ $self->{props} } };
    return wantarray ? %$props : $props;
}

sub has {
    my ( $self, $property ) = @_;
    return $self->{props}->{$property} ? 1 : 0;
}

sub tags {
    my $self = shift;
    my @tags;
    if ( $self->has('tags') ) {
        @tags = grep { !s:^Notebooks/:: } $self->property('tags');
    }
    return wantarray ? @tags : \@tags;
}

sub has_tag {
    my ( $self, $tag ) = @_;
    my %tag = map { $_ => 1 } $self->tags;
    return $tag{$tag};
}

sub in_notebook {
    my ( $self, $notebook ) = @_;
    my %notebook = map { $_ => 1 } $self->notebooks;
    return $notebook{$notebook};

}

sub notebooks {
    my $self = shift;
    my @notebooks;
    if ( $self->has('tags') ) {
        @notebooks = grep {s:^Notebooks/::} $self->property('tags');
    }
    return wantarray ? @notebooks : \@notebooks;
}

sub title {
    my $self  = shift;
    my $title = $self->property('title');
    return $title;
}

sub _datetime {
    my ( $self, $modified_or_created ) = @_;
    unless ( $self->{$modified_or_created} ) {
        $self->{$modified_or_created} = DateTime::Format::ISO8601->parse_datetime( $self->property($modified_or_created) );
        unless ( $self->{$modified_or_created} ) {
            $self->{$modified_or_created} = DateTime->now;
        }
    }
    return $self->{$modified_or_created};
}

sub modified {
    my $self = shift;
    return $self->_datetime('modified');
}

sub created {
    my $self = shift;
    return $self->_datetime('created');
}

sub _modified_now {
    my $self = shift;
    $self->{modified}          = DateTime->now;
    $self->{props}->{modified} = $self->{modified}->iso8601 . 'Z';
    $self->{changed}           = 1;
}

sub file {
    my $self = shift;
    return $self->{file};
}

sub filename {
    my $self = shift;
    return $self->{file};
}

sub attachments {
    my $self        = shift;
    my $attachments = $self->property('attachments');
    $attachments = [] unless ($attachments);
    return wantarray ? @$attachments : $attachments;
}

# get contents of note
sub _get_content {
    my ( $self, $header_only ) = @_;

    if ( !exists $self->{content} ) {
        my $fh = IO::File->new( $self->{opt}->{notes_dir} . $self->{file}, "r" ) || die "File open fail";
        $fh->binmode(":utf8");

        # read header
        $self->{header} = <$fh>;
        if ( $self->{header} !~ m/^---/ ) {    # no YAML header
            $self->{content} = $self->{header};
            $self->{header}  = undef;
        }
        else {
            while (<$fh>) {
                if (m/^(?:---|\.\.\.)/) {      # end of header
                    my $possible_newline = <$fh>;
                    if ( $possible_newline !~ m:^\s*$: ) {
                        $self->{content} = $possible_newline;    # not a newline
                    }
                    last;
                }
                $self->{header} .= $_;
            }
        }

        # read contents
        unless ($header_only) {
            $self->{content} = '' unless ( exists $self->{content} );

            while (<$fh>) {
                $self->{content} .= $_;
            }
        }
        else {
            delete $self->{content};
        }
        $fh->close;
    }
    return $self->{content};
}

sub content {
    my $self = shift;
    if (@_) {
        $self->{content} = shift;
        $self->_modified_now;
    }
    else {
        $self->_get_content;
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
