#!/usr/bin/perl
use DBI;
my $dbh = DBI->connect("dbi:SQLite:heritage.db");
use EraEight::Import;
EraEight::Import->import_simple_table($dbh, $_) for (
#    "REV40000", 
#    "REV40044", 
#    "REV40045", 
#    "REV40065", 
#    "REV40031"
);

use EraEight::CatalogueImporter::DBI;
use EraEight::CatalogueImporter::KinoSearch;
my $cb = EraEight::CatalogueImporter::DBI->new("dbi:SQLite:heritage.db");
my $cb2 = EraEight::CatalogueImporter::KinoSearch->new("kinoindex");
EraEight::Import->import_main_catalogue($cb, $cb2);
