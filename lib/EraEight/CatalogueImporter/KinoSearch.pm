package EraEight::CatalogueImporter::KinoSearch;
use strict;
use KinoSearch;
use KinoSearch::Analysis::PolyAnalyzer;
use KinoSearch::InvIndexer;

sub new {
    my ($class, $path) = @_;
    my $self = bless {}, $class;
    $self->{analyzer} = KinoSearch::Analysis::PolyAnalyzer->new( language => 'en' );
    $self->{path} = $path;
    return $self;
}

sub setup_indexer {
    my $self = shift;
    $self->{invindexer} = KinoSearch::InvIndexer->new(
        invindex => $self->{path},
        create   => 1,
        analyzer => $self->{analyzer},
    );
    $self->{invindexer}->spec_field( name => "id", analyzed => 0, indexed => 0, stored => 1);
    $self->{invindexer}->spec_field( name => "year", analyzed => 0, stored => 0);
    $self->{invindexer}->spec_field( name => "classmark", analyzed => 0, stored => 0);
    for (qw/author editor title publisher/) {
        $self->{invindexer}->spec_field(name => $_, stored => 0);
    }
}

sub DESTROY {
    my $self = shift;
    $self->{invindexer}->finish;
}

sub index {
    my ($self, $book) = @_;
    if (!$self->{invindexer}) { $self->setup_indexer() }
    my $doc = $self->{invindexer}->new_doc;
    
    for (qw/year publisher id title/) {
        $doc->set_value( $_ => $book->{$_} ) if $book->{$_};
    }
    $doc->set_value( author => join " ", map { join " ", $_->{first}, $_->{last} } @{$book->{authors}});
    $doc->set_value( editor => join " ", @{$book->{editors}});
    $doc->set_value( classmark => join " ", @{$book->{editors}});
    $doc->set_boost($book->{score});
    $self->{invindexer}->add_doc($doc);
}

1;
