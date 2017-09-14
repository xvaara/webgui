package WebGUI::Content::Asset;

=head1 LEGAL

 -------------------------------------------------------------------
  WebGUI is Copyright 2001-2009 Plain Black Corporation.
 -------------------------------------------------------------------
  Please read the legal notices (docs/legal.txt) and the license
  (docs/license.txt) that came with this distribution before using
  this software.
 -------------------------------------------------------------------
  http://www.plainblack.com                     info@plainblack.com
 -------------------------------------------------------------------

=cut

use strict;
use LWP::MediaTypes qw(guess_media_type);
use Time::HiRes;
use WebGUI::Asset;
use WebGUI::PassiveAnalytics::Logging;

use Apache2::Const -compile => qw(OK);

=head1 NAME

Package WebGUI::Content::MyHandler

=head1 DESCRIPTION

A content handler that serves up assets.

=head1 SYNOPSIS

 use WebGUI::Content::Asset;
 my $output = WebGUI::Content::Asset::handler($session);

=head1 SUBROUTINES

These subroutines are available from this package:

=cut

#-------------------------------------------------------------------

=head2 dispatch ( $session, $assetUrl )

Attempts to return the output from an asset, based on its url.  All permutations of the
URL are tried, to find an asset that matches.  If it finds an Asset, then it calls the
dispatch method on it.  An Asset's dispatch always returns SOMETHING, so if a matching
asset is found, this is the last stop.

=head3 $session

A WebGUI::Session object.

=head4 $assetUrl

The URL for this request.

=cut

sub dispatch {
    my $session      = shift;
	my $assetUrl     = shift;
    $assetUrl        =~ s{/$}{};
    my $permutations = getUrlPermutations($assetUrl);
    foreach my $url (@{ $permutations }) {
        if (my $asset = getAsset($session, $url)) {
            ##Passive Analytics Logging
            WebGUI::PassiveAnalytics::Logging::log($session, $asset);
            # display from cache if page hasn't been modified.
            if ($session->user->isVisitor
             && !$session->http->ifModifiedSince($asset->getContentLastModified, $session->setting->get('maxCacheTimeout'))) {
                $session->http->setStatus("304","Content Not Modified");
                $session->http->sendHeader;
                $session->close;
                return "chunked";
            } 

            my $fragment = $assetUrl;
            $fragment =~ s/$url//;
            $session->asset($asset);
            my $output = eval { $asset->dispatch($fragment); };
            return $output if defined $output;
        }
    }
    $session->clearAsset;
    if ($session->var->isAdminOn) {
        my $asset = WebGUI::Asset->newByUrl($session, $session->url->getRefererUrl) || WebGUI::Asset->getDefault($session);
        return $asset->addMissing($assetUrl);
    }
    return undef;
}

#-------------------------------------------------------------------

=head2 getAsset ( session [, assetUrl ] )

Returns an asset based upon the requested asset URL, or optionally pass one in.

=cut

sub getAsset {
    my $session = shift;
	my $assetUrl = shift;
	my $asset = eval{WebGUI::Asset->newByUrl($session,$assetUrl,$session->form->process("revision"))};
	if ($@) {
		$session->errorHandler->warn("Couldn't instantiate asset for url: ".$assetUrl." Root cause: ".$@);
	}
    return $asset;
}

#-------------------------------------------------------------------

=head2 getRequestedAssetUrl ( session [, assetUrl ] )

Returns an asset based upon the requested asset URL, or optionally pass one in.

=cut

sub getRequestedAssetUrl {
    my $session = shift;
	my $assetUrl = shift || $session->url->getRequestedUrl;
    return $assetUrl;
}

#-------------------------------------------------------------------

=head2 getUrlPermutations ( $url )

Returns an array reference of permutations for the URL.

=head3 $url

The URL to permute.

=cut

sub getUrlPermutations {
    my $url          = shift;
    ##Handle empty urls (sitename only)
    return ['/'] if !$url
                 ||  $url eq '/';
    my @permutations = ();
    if ($url =~ /\.\w+$/) {
        push @permutations, $url;
        $url =~ s/\.\w+$//;
    }
    my @fragments = split /\//, $url;
    FRAG: while (@fragments) {
        last FRAG if $fragments[-1] eq '';
        push @permutations, join "/", @fragments;
        pop @fragments;
    }
    return \@permutations;
}

#-------------------------------------------------------------------

=head2 handler ( session ) 

The content handler for this package.

=cut

sub handler {
    my ($session) = @_;
    my ($errorHandler, $http, $var, $asset, $request, $config) = $session->quick(qw(errorHandler http var asset request config));
    my $output = "";
    if ($errorHandler->canShowPerformanceIndicators) { #show performance indicators if required
        my $t = [Time::HiRes::gettimeofday()];
        $output = dispatch($session, getRequestedAssetUrl($session));
        $t = Time::HiRes::tv_interval($t) ;
        if ($output =~ /<\/title>/) {
            $output =~ s/<\/title>/ : ${t} seconds<\/title>/i;
        } 
        else {
            # Kludge.
            my $mimeType = $http->getMimeType();
            if ($mimeType eq 'text/css') {
                $session->output->print("\n/* Page generated in $t seconds. */\n");
            } 
            elsif ($mimeType =~ m{text/html}) {
                $session->output->print("\nPage generated in $t seconds.\n");
            } 
            else {
                # Don't apply to content when we don't know how
                # to modify it semi-safely.
            }
        }
    } 
    else {
        $output = dispatch($session, getRequestedAssetUrl($session));
    }

    my $filename = $http->getStreamedFile();
    if ((defined $filename) && ($config->get("enableStreamingUploads") eq "1")) {
        my $ct = guess_media_type($filename);
        my $oldContentType = $request->content_type($ct);
        if ($request->sendfile($filename) ) {
            $session->close;
            return Apache2::Const::OK;
        } 
        else {
            $request->content_type($oldContentType);
        }
    }

    return $output;
}

1;
