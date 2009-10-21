package EraEight;
my $requests = 0;
our %args;
our $start;
our $VERSION = "1.00";
use Net::Amazon;
our $ua_us; 
our $ua_uk; 
my $hires_loaded = 0;
eval { require Time::HiRes; Time::HiRes->import(qw/gettimeofday tv_interval/); $hires_loaded = 1 };
use Data::Page;
use EraEight::DBI;
use List::Util qw/max/;
use Template;
use HTTP::Engine;
use HTTP::Engine::Middleware;
use strict;
use warnings;
use Class::DBI::Loader;
use KinoSearch::Searcher;
use KinoSearch::Analysis::PolyAnalyzer;
my $analyzer = KinoSearch::Analysis::PolyAnalyzer->new( language => 'en' );
my $searcher = KinoSearch::Searcher->new( invindex => 'kinoindex', analyzer => $analyzer);
my $query_parser = KinoSearch::QueryParser::QueryParser->new(
    analyzer => $analyzer, fields   => [ 'title', 'author', 'editor' ],
    default_boolop => 'AND',
);

sub import {
    my $self = shift;
    %args = ( # Defaults go first
        dsn => "dbi:SQLite:heritage.db",
        interface => "ServerSimple",
        template_path => ["user_templates", "templates"],
        port => "4848",
        host => "0.0.0.0",
        @_
    );
    my $mw = HTTP::Engine::Middleware->new( { method_class => 'HTTP::Engine::Request' });
    if (!$args{amazon_key_id}) { die "You need to include your Amazon key" };
    if (!$args{amazon_secret_key}) { die "You need to include your Amazon secret" };
    $ua_us = Net::Amazon->new(token => $args{amazon_key_id}, secret_key => $args{amazon_secret_key}); 
    $ua_uk = Net::Amazon->new(token => $args{amazon_key_id}, secret_key => $args{amazon_secret_key}, locale=>"uk");

    use EraEight::DBI;
    EraEight::DBI->load($args{dsn});
    for (@{ref($args{template_path}) ? $args{template_path} : [$args{template_path}]}) {
        $mw->install( 'HTTP::Engine::Middleware::Static' => {
            regexp  => qr{^/static/(.+)$},
            docroot => $_,
            is_404_handler => 0,
        });
    }
    my $t = Template->new({
        INCLUDE_PATH => $args{template_path},
        PRE_PROCESS  => "header",
        POST_PROCESS => "footer",
        COMPILE_DIR => $args{compiled_templates},
        COMPILE_EXT => ".ttc"
    });
    HTTP::Engine->new(
        interface => {
            module => $args{interface},
            args   => { %args },
            request_handler => $mw->handler(sub {$_[0]->{template}=$t;handle_request(@_)}),
        },
    )->run;
}

sub new { bless {}, shift } # For templates

sub handle_request {
    my $req = shift;
    $start = $hires_loaded ? [gettimeofday()] : 0;
    my $page;
    my $res = HTTP::Engine::Response->new;
    my (undef, $action, @args) = split /\//,  $req->path;
    if (defined $action and $action eq "details") { return EraEight->details($req) }
    my $q = $req->parameters()->{q};
    if ($q) { 
        my ($pager, @books) = search($q, $req->parameters()->{page}, $req->parameters()->{epp});
        return EraEight->respond($req, "", "results", books => \@books, pager => $pager);
    }
    return EraEight->respond($req, "", "searchbox");
}

sub _try_amazon {
    my ($isbn, $ua) = @_;
    return unless $ua;
    my $response = $ua->search(asin => $isbn);
    if (!$response->is_success()) { return; }
    my ($prop) = $response->properties;
    EraEight::Amazon->create({
        book => $isbn,
        map {lc$_ => $prop->$_() } qw/ImageUrlMedium ImageUrlLarge ProductDescription/
    });
}

sub details {
    my ($self, $req) = @_;
    my ($book) = EraEight::Books->search(book => $req->parameters()->{book});
    if (!$book) { return EraEight->respond($req, "", "searchbox"); }
    if ($book->book =~ /^[0-9X]{10}$/ and !$book->amazon and fork) {
        _try_amazon($book->book, $ua_us) ||
        _try_amazon($book->book, $ua_uk);
        exit;
    }
    return EraEight->respond($req, "", "details", book => $book);
}

sub respond {
    my ($self, $req, $action, $template, @args) = @_;
    my $out;
    my $res = HTTP::Engine::Response->new();
    $req->{template}->process($template, { 
        @args,
        action => $action, 
        req => $req, 
        args => \%args,
        e8 => EraEight->new(),
        }, \$out) ? $res->body($out) : $res->body($req->{template}->error);
    return $res;
}

sub timecheck {
    return unless $hires_loaded;
    return tv_interval ( $start, [gettimeofday()]);
}

sub its_all_gone_wrong {
    my $self = shift;
    my $res = HTTP::Engine::Response->new();
    $res->body(shift);
    return $res;
}

sub search {
    my $query = $query_parser->parse( shift  );
    my $hits  = $searcher->search( query => $query );
    my $p = Data::Page->new();
    $p->total_entries($hits->total_hits);
    $p->current_page(shift || 1);
    $p->entries_per_page(shift || 10);
    my @r;
    my $things;
    return unless $hits->total_hits;
    $hits->seek($p->first - 1, $p->entries_on_this_page );
    while ( my $hit = $hits->fetch_hit_hashref ) {
        push @r,EraEight::Books->search(book => $hit->{id})->first;
    }
    return $p, @r;
}
1;
