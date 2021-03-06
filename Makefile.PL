use inc::Module::Install;
name        'EraEight';
abstract    'Online catalogue for Heritage library databases';
author      'Simon Cozens <simon@simon-cozens.org>';
include     'Module::AutoInstall';
license     'artistic';
perl_version '5.006';
all_from    "lib/EraEight.pm",
requires	"KinoSearch" => 0;
requires	"Plack" => 0.9017;
requires    "Test::TCP" => 0.15;
requires	"Plack::Request" => 0;
requires	"List::Util" => 0;
requires	"Net::Amazon" => 0;
requires	"File::Slurp" => 0;
requires	"DBI" => 0;
requires	"Data::Page" => 0;
requires	"HTTP::Session" => 0;
requires	"Class::DBI::Loader" => 0;
requires	"Class::DBI::SQLite" => 0;
requires	"DBD::SQLite" => 1.27;
requires	"Template" => 0;
requires	"Time::Piece" => 0;
requires    "HTTP::BrowserDetect" => 0;
recommends  "Time::HiRes" => 0;
auto_install;
WriteAll;
