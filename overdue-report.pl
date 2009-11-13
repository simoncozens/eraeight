use lib 'lib';
use EraEight;
use Time::Seconds;
EraEight::DBI->load("dbi:SQLite:heritage.db");
use constant GRACE => 5;
for my $bo (EraEight::Booksout->search_overdue) {
    my $days = int( (Time::Piece->new($bo->day_due)-Time::Piece->new()) / ONE_DAY );
    next if $days < GRACE;
    my ($f, $l) = ($bo->userid->first,$bo->userid->last);
    push @over, { book => $bo->accession->book, first => $f, last => $l,
        name => "$f $l", over => $days };
}

my $last_over = 0; my $lastname;
for (sort { $b->{over} <=> $a->{over} || $a->{name} cmp $b->{name} } @over) {
    if ($_->{over} != $last_over) { 
        print "\n\t**** $_->{over} days overdue ****\n";
        $last_over = $_->{over};
    }
    if ($lastname ne $_->{name}) { print "\n$_->{name}:\n"; $lastname = $_->{name}; }
    print "\t";
    print $_->{book}->title, "\n";
}

