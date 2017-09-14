package WebGUI::Session::Plack;

use strict;
use warnings;
use Carp;

=head1 DESCRIPTION

This class is used instead of WebGUI::Session::Request when wg is started via plackup

=cut

sub new {
    my ( $class, %p ) = @_;

    # 'require' rather than 'use' so that non-plebgui doesn't freak out
    require Plack::Request;
    my $request  = Plack::Request->new( $p{env} );
    my $response = $request->new_response(200);

    bless {
        %p,
        pnotes   => {},
        request  => $request,
        response => $response,
        server   => WebGUI::Session::Plack::Server->new( env => $p{env} ),
        headers_out => Plack::Util::headers( [] ),    # use Plack::Util to manage response headers
        body        => [],
        sendfile    => undef,
    }, $class;
}

our $AUTOLOAD;

sub AUTOLOAD {
    my $what = $AUTOLOAD;
    $what =~ s/.*:://;
    carp "!!plack->$what(@_)" unless $what eq 'DESTROY';
}

# Emulate/delegate/fake Apache2::* subs
sub uri         { shift->{request}->path_info }
sub param       {
    my $self = shift;
    if (@_) {
        return $self->{request}->param(@_);
    }
    else {
        return $self->params;
    }
}
sub params      { shift->{request}->parameters->mixed(@_) }
sub headers_in  { shift->{request}->headers(@_) }
sub headers_out { shift->{headers_out} }
sub protocol    { shift->{request}->protocol(@_) }
sub status      { shift->{response}->status(@_) }
sub sendfile    { $_[0]->{sendfile} = $_[1] }
sub server      { shift->{server} }
sub method      { shift->{request}->method }
sub upload      { shift->{request}->upload(@_) }
sub dir_config  { shift->{server}->dir_config(@_) }
sub status_line { }
sub auth_type   { }                                     # should we support this?
sub handler     {'perl-script'}                         # or not..?

sub content_type {
    my ( $self, $ct ) = @_;
    $self->{headers_out}->set( 'Content-Type' => $ct );
}

# TODO: I suppose this should do some sort of IO::Handle thing
sub print {
    my $self = shift;
    # Make sure we'll never output wide chars because plack will die when we do.
    foreach ( @_ ) {
        utf8::encode( $_ ) if utf8::is_utf8( $_ );
        push @{ $self->{body} }, $_;
    }
}

sub pnotes {
    my ( $self, $key ) = ( shift, shift );
    return wantarray ? %{ $self->{pnotes} } : $self->{pnotes} unless defined $key;
    return $self->{pnotes}{$key} = $_[0] if @_;
    return $self->{pnotes}{$key};
}

sub user {
    my ( $self, $user ) = @_;
    if ( defined $user ) {
        $self->{user} = $user;
    }
    $self->{user};
}

sub push_handlers {
    my $self = shift;
    my ( $x, $sub ) = @_;

    # log it
    # carp "push_handlers($x)";

    # run it
    # returns something like Apache2::Const::OK, which we just ignore because we're not modperl
    my $ret = $sub->($self);

    return;
}

sub finalize {
    my $self     = shift;
    my $response = $self->{response};
    if ( $self->{sendfile} && open my $fh, '<', $self->{sendfile} ) {
        $response->body($fh);
    }
    else {
        $response->body( $self->{body} );
    }
    $response->headers( $self->{headers_out}->headers );
    return $response->finalize;
}

sub no_cache {
    my ( $self, $doit ) = @_;
    if ($doit) {
        $self->{headers_out}->set( 'Pragma' => 'no-cache', 'Cache-control' => 'no-cache' );
    }
    else {
        $self->{headers_out}->remove( 'Pragma', 'Cache-control' );
    }
}

################################################

package WebGUI::Session::Plack::Server;

use strict;
use warnings;
use Carp;

sub new {
    my $class = shift;
    bless {@_}, $class;
}

our $AUTOLOAD;

sub AUTOLOAD {
    my $what = $AUTOLOAD;
    $what =~ s/.*:://;
    carp "!!server->$what(@_)" unless $what eq 'DESTROY';
}

sub dir_config {
    my ( $self, $c ) = @_;

    # Translate the legacy WebguiRoot and WebguiConfig PerlSetVar's into known values
    return WebGUI->root if $c eq 'WebguiRoot';
    return WebGUI->config_file if $c eq 'WebguiConfig';

    # Otherwise, we might want to provide some sort of support (which Apache is still around)
    return $self->{env}->{"wg.DIR_CONFIG.$c"};
}

################################################

package Plack::Request::Upload;

sub link {
    my $self    = shift;
    my $target  = shift;
    require File::Copy;

    File::Copy::copy( $self->path, $target ) or die "copy failed $!, $@";
}

1;
