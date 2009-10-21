package EraEight::CatalogueImporter::DBI;
use strict;
use DBI;

sub new {
    my ($class, @db_connect_args) = @_;
    my $self = bless {}, $class;
    $self->{dbh} = DBI->connect(@db_connect_args) or die "Couldn't connect to database $db_connect_args[0]";
    return $self;
}

sub prepare {
    my $self = shift; my $dbh = $self->{dbh};
    $dbh->do("CREATE TABLE IF NOT EXISTS authors (id integer primary key not null, book, firstname, lastname);");
    $dbh->do("CREATE TABLE IF NOT EXISTS editors (book, name);");
    $dbh->do("CREATE TABLE IF NOT EXISTS classmarks (book, classmark);");
    $dbh->do("CREATE TABLE IF NOT EXISTS catcode$_ (book, category);") for 1..3;
    $dbh->do("CREATE TABLE IF NOT EXISTS books ( book, title, media, edition, address, publisher, year, dimensions, series, notes );");

    $self->{ $_ } = $dbh->prepare_cached("INSERT INTO $_ VALUES (?, ?)")
        for qw(classmarks catcode1 catcode2 catcode3 editors);
    $dbh->do("create index if not exists accession_lookup on accessions (accession)");
    $dbh->do("create index if not exists book_lookup on books (book)");
    $self->{loans} = $dbh->selectall_hashref("select book, count(*) loancount from accessions, loanhistory where loanhistory.accession = accessions.accession group by book order by count(*)", "book");

    $self->{books_we_have} = $dbh->selectall_hashref("SELECT DISTINCT book FROM accessions", "book");
    $self->{auth} = $dbh->prepare_cached("INSERT INTO authors (book, firstname, lastname) VALUES (?, ?, ?)");
    $self->{book} = $dbh->prepare_cached("INSERT INTO books VALUES (?,?,?,?,?,?,?,?,?,?)");
}

sub clearout {
    my $dbc = shift;
    $dbc->{dbh}->do("DROP TABLE IF EXISTS $_")
        for qw/books authors editors classmarks catcode1 catcode2 catcode3/;
}

sub index {
    my ($self, $book) = @_;
    $self->{auth}->execute($book->{id}, $_->{"first"}, $_->{"last"}) 
        for @{ $book->{"authors"} };
    $self->{book}->execute(@{$book}{qw/id title media edition address publisher year dimensions series notes/});

    # Loop unrolled for speed/memory
    $self->{editors}->execute($book->{id}, $_) for @{ $book->{"editors"} };
    $self->{classmarks}->execute($book->{id}, $_) for @{ $book->{"classmarks"} };
    $self->{catcode1}->execute($book->{id}, $_) for @{ $book->{"catcode1"} };
    $self->{catcode2}->execute($book->{id}, $_) for @{ $book->{"catcode2"} };
    $self->{catcode3}->execute($book->{id}, $_) for @{ $book->{"catcode3"} };
}

1;
