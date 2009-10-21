#!/usr/bin/perl
use DBI;
my $dir = shift;
if (!-d $dir) {
    die "Usage: $0 <heritage catalogue directory>

The heritage catalogue directory usually looks like
   something/heri4/windata
";
}
my $dbh = DBI->connect("dbi:SQLite:heritage.db");
use EraEight::Import;
use File::Basename;
EraEight::Import->import_simple_table($dbh, $_) for 
    grep { exists $EraEight::Import::tables{basename $_} }
    map { s/\.OV$//i; $_ }
    glob("$dir/*.OV");

use EraEight::CatalogueImporter::DBI;
use EraEight::CatalogueImporter::KinoSearch;
my $cb = EraEight::CatalogueImporter::DBI->new("dbi:SQLite:heritage.db");
my $cb2 = EraEight::CatalogueImporter::KinoSearch->new("kinoindex");
#EraEight::Import->import_main_catalogue($cb, $cb2);
