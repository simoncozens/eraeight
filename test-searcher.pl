    use KinoSearch::Searcher;
    use KinoSearch::Analysis::PolyAnalyzer;
    use EraEight::DBI;
    
    my $analyzer = KinoSearch::Analysis::PolyAnalyzer->new( language => 'en' );
    
    my $searcher = KinoSearch::Searcher->new(
        invindex => 'kinoindex',
        analyzer => $analyzer,
    );
    
    my $query_parser = KinoSearch::QueryParser::QueryParser->new(
        analyzer => $analyzer,
        fields   => [ 'title', 'author' ],
        default_boolop => 'AND',           # default: 'OR'
    );
    my $query = $query_parser->parse( shift @ARGV );
    my $hits  = $searcher->search( query => $query );

    EraEight::DBI->load("dbi:SQLite:heritage.db");
    while ( my $hit = $hits->fetch_hit_hashref ) {
        my $book = EraEight::Books->search(book => $hit->{id})->first;
        print $book->title," (",$book->authors, ", ",$book->year,")\n";
    }
