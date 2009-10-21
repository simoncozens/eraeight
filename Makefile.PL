use ExtUtils::MakeMaker;
WriteMakefile(
    NAME => "EraEight",
    VERSION_FROM => "lib/EraEight.pm",
    PREREQ_PM => { 
        KinoSearch => 0,
        HTTP::Engine => 0,
        HTTP::Engine::Middleware => 0,
        List::Util => 0,
        Net::Amazon => 0,
        File::Slurp => 0,
        DBI => 0,
        Data::Page => 0,
        Class::DBI::Loader => 0,
        Class::DBI::Loader::SQLite => 0,
        DBD::SQLite => 0,
        Template => 0,
        Time::Piece => 0,
    }
);

