package EraEight::Import;
use File::Basename;
use strict;
$EraEight::Import::progress = 0;
use File::Slurp;
use DBI;

our %tables = (
    REV40000 => [accessions => qw/accession book status loantype location category copies/],
    REV40001 => [accessionstatus => qw/status desc/],
    REV40013 => [loanhistory => qw/timestamp accession userid/],
    REV40031 => [booksout => qw/accession userid status timestamp day_issued day_due /],
    REV40044 => [users => qw/userid title first last address phone status/],
    REV40045 => [userstatus => qw/status desc /],
);

our %complex_tables = (
    REV40065 => [subjects => qw/code desc bookcount classmarks books/],
    
);

use Time::Piece;
use Time::Seconds;

my $pick_epoch = Time::Piece->strptime("1967-12-31", "%F");
sub pick2unix { return ($pick_epoch + ONE_DAY*shift)->epoch }

my %directory;
# Heritage uses random-casing on its files. Urgh.
sub smashcase {
    my $file = shift;
    %directory = map { uc$_ => $_} glob(dirname($file)."/*.*") unless %directory;
    return $directory{uc $file};
}
sub import_simple_table {
    my ($self, $dbh, $file) = @_;
    if (!exists $tables{basename $file}) { die "$file isn't a simple table, can't import!"; }
    my ($tablename, @cols) = @{$tables{basename $file}};
    $dbh->{RaiseError} = 1;
    return unless file_has_changed($dbh, $file, $tablename);
    $dbh->{AutoCommit} = 0;
    eval { 
        $dbh->do("DROP TABLE $tablename");
        $dbh->do("CREATE TABLE $tablename (".join(",",@cols).");");
        my $sth = $dbh->prepare_cached("INSERT INTO $tablename VALUES (".
            join("," ,map { "?" } @cols).")");
        my $data = read_file(smashcase("$file.OV")).(-e smashcase("$file.LK") && read_file(smashcase("$file.LK")));
$data||die "No data for $file!";
        my @records = split /(?=.[\200-\220])/ms, $data;
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
            for (0..$#cols) {
                if ($cols[$_] =~ /day_/) { $rows[$_] = pick2unix($rows[$_]); }
            }
            $sth->execute(@rows[0..$#cols]);
        }
        if ($EraEight::Import::progress) {print "\n"}
        $dbh->commit;
    };
    if ($@) {
        warn "Transaction aborted because $@";
        eval { $dbh->rollback };
    }
    successful_import($dbh, $file, $tablename);
}

sub _timestamp {
    my $file = shift;
    my ($timestampl, $timestampo) = ((stat(smashcase($file.".LK")))[9], (stat(smashcase($file.".OV")))[9]);
    return [$timestampl => $timestampo]->[$timestampl <= $timestampo];
}

sub file_has_changed {
    my ($dbh, $file, $tablename) = @_;
    $dbh->do("CREATE TABLE IF NOT EXISTS importhistory (tablename, timestamp)");
    my $import = $dbh->selectall_hashref("SELECT tablename, max(timestamp) lastimport FROM importhistory GROUP BY tablename", "tablename");
    if ($import->{$tablename} and $import->{$tablename}->{lastimport} >= _timestamp($file)) {
        print "$tablename is current, skipping\n" if $EraEight::Import::progress;
        return 0;
    }
    return 1;
}

sub successful_import {
    my ($dbh, $file, $tablename) = @_;
    $dbh->do("INSERT INTO importhistory VALUES (?, ?)", {}, $tablename, _timestamp($file));
    $dbh->commit;
}

sub import_main_catalogue {
    my ($self, $datadir, @callbacks) = @_;
    my ($dbc) = grep { ref $_ eq "EraEight::CatalogueImporter::DBI" } @callbacks;
    die "At least one callback needs to be DBI backed, and you need to have imported accessions already " unless $dbc;
    $dbc->{dbh}->{AutoCommit} = 0;
    $dbc->{dbh}->{RaiseError} = 1;
    return unless file_has_changed($dbc->{dbh}, "$datadir/REV40033", "catalogue");
    eval {
        $dbc->clearout();
        $dbc->prepare();
        _do_one_catalogue("$datadir/REV40033.LK", @callbacks);
        _do_one_catalogue("$datadir/REV40033.OV", @callbacks);
        $dbc->{dbh}->commit;
    };
    if ($@) {
        warn "Transaction aborted because $@";
        eval { $dbc->{dbh}->rollback };
    }
    successful_import($dbc->{dbh}, "$datadir/REV40033", "catalogue");
}

sub _do_one_catalogue {
    my ($filename, @callbacks) = @_;
    $filename = smashcase($filename);
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
            next unless $dbc->{books_we_have}->{$id};
            my @rows = split /\xfe/;
            my $score = 1;
            if ($dbc->{loans}{$id}) { $score = (1+$dbc->{loans}{$id}{loancount}) } 
            my $book = { 
                id => $id,
                score      => $score,
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
