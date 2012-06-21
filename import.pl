#!/usr/bin/perl
use FindBin qw($Bin);
use lib "$Bin/lib";
do "$Bin/e8-server.psgi";
use DBI;
my $dir = shift;
if (!-d $dir) {
    die "Usage: $0 <heritage catalogue directory>

The heritage catalogue directory usually looks like
   something/heri4/windata
";
}
my $dbh = DBI->connect($EraEight::args{dsn});
use EraEight::Import;
use File::Basename;
EraEight::Import->import_simple_table($dbh, $_) for 
    grep { exists $EraEight::Import::tables{uc basename $_} }
    map { s/\.OV$//i;  $_ }
    (glob("$dir/*.OV"), glob("$dir/*.ov"));

use EraEight::CatalogueImporter::DBI;
use EraEight::CatalogueImporter::KinoSearch;
my $cb = EraEight::CatalogueImporter::DBI->new($EraEight::args{dsn});
my $cb2 = EraEight::CatalogueImporter::KinoSearch->new("kinoindex");
EraEight::Import->import_main_catalogue($dir, $cb, $cb2);
