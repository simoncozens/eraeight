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
use Plack::Builder;
use HTTP::Session::Store::File;
use HTTP::Session::State::Cookie;


# The "web framework"

sub app { 
    my $self = shift;
    %args = ( # Defaults go first
        dsn => "dbi:SQLite:heritage.db",
        sessiondir => "/tmp/eraeight",
        template_path => [ "user_templates", "templates"],
        @_
    );
    if (!-d $args{sessiondir}) { mkdir $args{sessiondir} or die "Couldn't create session directory" }
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
    builder {
      enable "Plack::Middleware::HTTPSession",
           store => HTTP::Session::Store::File->new(dir => $args{sessiondir}),
           state => HTTP::Session::State::Cookie->new(name => "eraeight");
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
    };
}

sub new { bless {}, shift } # For templates

sub handle_request {
    my ($self, $req) = @_;
    $start = $hires_loaded ? [gettimeofday()] : 0;
    my $page;
    my $res = Plack::Response->new;
    my (undef, $action, @args) = split /\//,  $req->path;
    my $sess = $req->env->{"psgix.session"};
    if (defined $action and $action =~ /^(add_to_cart|view_cart|details|empty_cart)$/) { return $self->$action($req) }
    my $q = $req->parameters()->{q};
    if ($q) { 
        my ($pager, @books) = search($q, $req->parameters()->{page}, $req->parameters()->{epp});
        if ($req->parameters()->{btnI}) { return $self->details($req, $books[0]) }
        my $hints = $self->searchhints($q, \@books);
        return $self->respond($req, "results", books => \@books, pager => $pager, hints => $hints);
    }
    return $self->respond($req, "searchbox");
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
        sess => $req->env->{"psgix.session"},
        e8 => EraEight->new(),
        }, \$out) ? $res->body($out) : $res->body($self->{template_engine}->error);
    return $res;
}

# The actions

sub details {
    my ($self, $req, $book) = @_;
    ($book) = EraEight::Books->search(book => $req->parameters()->{book})
        if !$book;
    if (!$book) { return $self->respond($req, "searchbox"); }
    if ($book->book =~ /^[0-9X]{10}$/ and !$book->amazon) {
        _try_amazon($book->book, $ua_us) ||
        _try_amazon($book->book, $ua_uk);
    }
    return $self->respond($req, "details", book => $book);
}

sub view_cart {
    my ($self, $req) = @_;
    my $sess = $req->env->{"psgix.session"};
    my $books = $sess->get("books") || [];
    my @books = 
        sort { ($a->authors)[0]->lastname cmp ($b->authors)[0]->lastname }
        map { EraEight::Books->search(book => $_) } @$books;
    return $self->respond($req, "view_cart", books => \@books);
}

sub add_to_cart {
    my ($self, $req) = @_;
    my $sess = $req->env->{"psgix.session"};
    my $books = $sess->get("books") || [];
    my ($book) = EraEight::Books->search(book => $req->parameters()->{book});
    $sess->set("books", [@$books, $book]);
    my $res = Plack::Response->new();
    $res->body("OK"); $res->status(200);
    return $res;
}

sub empty_cart {
    my ($self, $req) = @_;
    my $sess = $req->env->{"psgix.session"};
    $sess->set("books", undef);
    return $self->respond($req, "searchbox");
}
# Utility methods

sub timecheck {
    return unless $hires_loaded;
    return tv_interval ( $start, [gettimeofday()]);
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

sub searchhints {
    my ($self, $q, $books) = @_;
    if ($q =~ /(?:\b|^)(1\d\d\d)/ and $q !~ /year:/i) { return "You can find books published in $1 by adding <b>year:$1</b> to your search" }
    for (@$books) { 
        if ($q !~ /author:/i) { 
        for (map {$_->lastname} $_->authors) {
            return "You can find books written by '$_' by adding <b>author:$_</b> to your search" if $q =~ /(\b|^)$_\b/i;
        }
        }
    }
    my @advice = ("Find books published by Lion by searching for <b>publisher:Lion</b>",
    "EraEight knows about common plurals and suffixes, so looking up <b>Christianity</b>, <b>Christians</b> and <b>Christian</b> all give the same results",
    "You can find books by title, author, year, publisher, editor and classmark. Just search for, e.g. <b>publisher:orbis author:koyama</b>",
    "If Google Books has a preview of a book, then we'll provide a link to it",
    "We try to find descriptions and pictures of books from Amazon where possible",
    "You can use a minus sign to negate search terms. If you want books about salvation but not about the Salvation Army, say <b>salvation -army</b>",
    "Normally all search terms have to be present for a book to show up but you can change that using brackets and upper-case <b>OR</b>. If you want books on Mahayana Buddhism, try <b>(chinese OR tibetan OR japanese) buddhism</b>."
    );
    if (rand() < 0.75) { return $advice[rand @advice] }
}
1;
