#!/usr/bin/perl
use Data::Dumper;
$Data::Dumper::Indent=0;
our %tables = (
    REV40000 => [accessions => qw/accession book status loantype location category copies/],
    REV40031 => [booksout => qw/accession userid status timestamp issued returndate /],
    REV40044 => [users => qw/userid title first last status/],
    REV40045 => [userstatus => qw/status desc /],
    REV40065 => [catcode3desc => qw/code desc /],

);

for (sort keys %tables) { 
    dump_a_file($_.".OV", $tables{$_}); 
    dump_a_file($_.".LK", $tables{$_}); 
}

sub dump_a_file {
    my ($fname, $stuff) = @_;
    open IN, $fname or do {print "$!: $fname\n"; return};
    my $data = do {local $/; <IN>};
    my ($name, @cols) = @$stuff;
    print "\t\t$fname - $name table\t\t\n\n";
format STDOUT_TOP = 
@<<<<<<... @<<<<<<... @<<<<<<... @<<<<<<... @<<<<<<... @<<<<<<... @<<<<<<...
@cols
.
    my @records = split /(?=.[\200-\210])/ms, $data;
    my $count = 0;
    for (@records) {
        s/\0+//g; next unless /\xfe/; s/^(.)(.)// or next;
        my $id = substr($_, 0, ord($2)-128, "");
        next unless $id;
        s/\375/ and /g;
        my @rows = ($id, split /\xfe/, $_);
format STDOUT = 
@<<<<<<... @<<<<<<... @<<<<<<... @<<<<<<... @<<<<<<... @<<<<<<... @<<<<<<...
@rows
.
        write;
        last if $count++ > 2;
    }
    print "...\n\n\n";
    $- = 0;
}

# Now let's try to read the catalogue
_do_one_catalogue("REV40033.LK");
_do_one_catalogue("REV40033.OV");

sub _do_one_catalogue {
    my ($filename, @callbacks) = @_;
    open my $in, $filename or die "Couldn't open $filename: $!";
    local $/="\0\0\0"; # Good as anything.
    my $cc = 0;
    while (<$in>) {
        my @records = split /(?=[\x00-\x0f])/ms, $_;
        for (@records) {
            next unless /\xfe/;
            s/^([\x00-\x0f].)(.)// or next;
            $cc++; 
            return if $cc > 4;
            my $id = substr($_, 0, ord($2)-128, "");
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
            print "Book $id: $book->{title}, ($book->{publisher}) by ";
            while (@firsts || @lasts) { 
                print shift @firsts, " ", shift @lasts,"  ";
            }
            print "\n\n";
        }
    }
}
1;
