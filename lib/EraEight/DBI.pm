package EraEight::DBI;
use Class::DBI::Loader;
use Time::Piece;

sub load {
    my ($self, $dsn, $u, $p) = @_;
    my $loader = Class::DBI::Loader->new(
        dsn => $dsn,
        user => $u,
        password => $p,
        namespace => "EraEight",
        options => { AutoCommit => 1 },
        relationships => 1,
    );
    foreach my $table ($loader->tables) {
        #$loader->find_class($table)->db_Main->func(5, 'busy_timeout');
    }
    $_->has_a("book" => "EraEight::Books")
        for qw/EraEight::Authors EraEight::Classmarks EraEight::Accessions/;
    $_->has_a("userid" => "EraEight::Users") for qw/EraEight::Booksout/;
    EraEight::Books->has_many("authors" => "EraEight::Authors");
    EraEight::Books->has_many("holdings" => "EraEight::Accessions");
    EraEight::Books->has_many("classmarks" => "EraEight::Classmarks");
    EraEight::Booksout->has_a("accession" => "EraEight::Accessions");
    EraEight::Booksout->set_sql(overdue => "SELECT * FROM booksout where day_due < ?");
}

sub EraEight::Books::amazon { 
    my ($a) = EraEight::Amazon->search(book => shift->book);
    return $a;
}
sub EraEight::Accessions::on_loan {
    my ($loan) = EraEight::Booksout->search(accession  => shift->accession);
    return unless $loan;
    return { to => $loan->userid->first()." ".$loan->userid->last(),
             due => Time::Piece->new($loan->day_due),
             overdue => (time > $loan->day_due)
           };
}
1;
