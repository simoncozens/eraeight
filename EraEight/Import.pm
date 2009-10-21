package EraEight::Import;
use strict;
$EraEight::Import::progress = 1;
use File::Slurp;
use DBI;

our %tables = (
    REV40000 => [accessions => qw/accession book status loantype location category copies/],
    REV40031 => [booksout => qw/accession userid status timestamp issued returndate /],
    REV40044 => [users => qw/userid title first last status/],
    REV40045 => [userstatus => qw/status desc /],
    REV40065 => [catcode3desc => qw/code desc /],

);

sub import_simple_table {
    my ($self, $dbh, $file) = @_;
    if (!exists $tables{$file}) { die "$file isn't a simple table, can't import!"; }
    my ($tablename, @cols) = @{$tables{$file}};
    $dbh->do("CREATE TABLE IF NOT EXISTS $tablename (".join(",",@cols).");");
    my $sth = $dbh->prepare_cached("INSERT INTO $tablename VALUES (".
        join("," ,map { "?" } @cols).")");
    my $data = read_file("$file.ov").(-e "$file.lk" && read_file("$file.lk"));
    my @records = split /(?=.[\200-\210])/ms, $data;
    if ($EraEight::Import::progress) { print "Importing $file ($tablename)\n" }
    my $cc = 0;
    if ($EraEight::Import::progress) { $| = 1; }
    for (@records) {
        s/\0+//g; next unless /\xfe/; s/^(.)(.)// or next;
        my $id = substr($_, 0, ord($2)-128, "");
        next unless $id;
            $cc++; 
            if ($EraEight::Import::progress) {
                print "." unless $cc % 100;
                print "+" unless $cc % 1000;
                print "\n" unless $cc % 5000;
            }
        s/\375/ and /g;
        my @rows = ($id, split /\xfe/, $_);
        $sth->execute(@rows[0..$#cols]);
    }
}

sub import_main_catalogue {
    my ($self, @callbacks) = @_;
    _do_one_catalogue("REV40033.LK", @callbacks);
    _do_one_catalogue("REV40033.OV", @callbacks);
}

sub _do_one_catalogue {
    my ($filename, @callbacks) = @_;
    open my $in, $filename or die "Couldn't open $filename: $!";
    my ($dbc) = grep { ref $_ eq "EraEight::CatalogueImporter::DBI" } @callbacks;
    die "At least one callback needs to be DBI backed, and you need to have imported accessions already " unless $dbc;
    local $/="\0\0\0"; # Good as anything.
    my $cc = 0;
    if ($EraEight::Import::progress) { $| = 1; }
    while (<$in>) {
        my @records = split /(?=[\x00-\x0f])/ms, $_;
        for (@records) {
            next unless /\xfe/;
            s/^([\x00-\x0f].)(.)// or next;
            $cc++; 
            if ($EraEight::Import::progress) {
                print "." unless $cc % 100;
                print "+" unless $cc % 1000;
                print "\n" unless $cc % 5000;
            }
            my $id = substr($_, 0, ord($2)-128, "");
            $dbc->{search}->execute($id);
            next unless @{$dbc->{search}->fetchall_arrayref};
            my @rows = split /\xfe/;
            my $book = { 
                id => $id,
                editors    => [ split /\375/, $rows[5]  ] ,
                classmarks => [ split /\375/, $rows[11] ] ,
                catcode1   => [ split /\375/, $rows[13] ] ,
                catcode2   => [ split /\375/, $rows[15] ] ,
                catcode3   => [ split /\375/, $rows[17] ] ,
                authors    => []
            };
            @{$book}{qw/title media edition address publisher year dimensions series notes/} = @rows[2,3,4,6,7,8,9,12, 14];
            my @firsts = split /\375/,$rows[0];
            my @lasts  = split /\375/,$rows[1];
            while (@firsts || @lasts) { 
                push @{$book->{authors}}, {first => shift(@firsts), last => shift(@lasts) };
            }
            $_->index($book) for @callbacks;
        }
    }
}
1;
