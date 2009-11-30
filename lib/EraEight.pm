package EraEight;
my $requests = 0;
our %args;
our $start;
our $VERSION = "1.00";
use Net::Amazon;
use Plack::Response;
our $ua_us; 
our $ua_uk; 
my $hires_loaded = 0;
eval { require Time::HiRes; Time::HiRes->import(qw/gettimeofday tv_interval/); $hires_loaded = 1 };
use Data::Page;
use EraEight::DBI;
use List::Util qw/max/;
use Template;
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
use Plack::Request;
use Plack::App::File;

sub app { 
    my $self = shift;
    %args = ( # Defaults go first
        dsn => "dbi:SQLite:heritage.db",
        template_path => [ "user_templates", "templates"],
        @_
    );
    if (!$args{amazon_key_id}) { die "You need to include your Amazon key" };
    if (!$args{amazon_secret_key}) { die "You need to include your Amazon secret" };
    $ua_us = Net::Amazon->new(token => $args{amazon_key_id}, secret_key => $args{amazon_secret_key}); 
    $ua_uk = Net::Amazon->new(token => $args{amazon_key_id}, secret_key => $args{amazon_secret_key}, locale=>"uk");

    use EraEight::DBI;
    EraEight::DBI->load($args{dsn});
    my $t = Template->new({
        INCLUDE_PATH => $args{template_path},
        PRE_PROCESS  => "header",
        POST_PROCESS => "footer",
        COMPILE_DIR => $args{compiled_templates},
        COMPILE_EXT => ".ttc"
    });
    sub { 
        my $env = shift;
        my $req = Plack::Request->new($env);
        # Fake static middleware because it won't let us have multiple
        # paths
        if ($req->path =~ /^\/static/) {
            for (@{ref($args{template_path}) ? $args{template_path} : [$args{template_path}]}) {
                next unless -f "$_/".$req->path;
                my $file = Plack::App::File->new({ root => $_ });
                return $file->call({ %$env, PATH_INFO => $env->{PATH_INFO} });
            }
            return [404, ['Content-Type' => 'text/plain'], ['not found']];
        }
        my $m = $self->new(%args);
        $m->{template_engine} = $t;
        $m->handle_request($req)->finalize;
    }
}

sub new { bless {}, shift } # For templates

sub handle_request {
    my ($self, $req) = @_;
    $start = $hires_loaded ? [gettimeofday()] : 0;
    my $page;
    my $res = Plack::Response->new;
    my (undef, $action, @args) = split /\//,  $req->path;
    if (defined $action and $action eq "details") { return $self->details($req) }
    my $q = $req->parameters()->{q};
    if ($q) { 
        my ($pager, @books) = search($q, $req->parameters()->{page}, $req->parameters()->{epp});
        if ($req->parameters()->{btnI}) { return $self->details($req, $books[0]) }
        return $self->respond($req, "results", books => \@books, pager => $pager);
    }
    return $self->respond($req, "searchbox");
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
    my ($self, $req, $book) = @_;
    ($book) = EraEight::Books->search(book => $req->parameters()->{book})
        if !$book;
    if (!$book) { return $self->respond($req, "searchbox"); }
    if ($book->book =~ /^[0-9X]{10}$/ and !$book->amazon and fork) {
        _try_amazon($book->book, $ua_us) ||
        _try_amazon($book->book, $ua_uk);
        exit;
    }
    return $self->respond($req, "details", book => $book);
}

sub respond {
    my ($self, $req, $template, @args) = @_;
    my $out;
    my $res = Plack::Response->new();
    $res->status(200);
    $self->{template_engine}->process($template, { 
        @args,
        req => $req, 
        args => \%args,
        e8 => EraEight->new(),
        }, \$out) ? $res->body($out) : $res->body($self->{template_engine}->error);
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
