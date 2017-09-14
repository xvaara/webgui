package WebGUI::Macro::AssetProxy;

#-------------------------------------------------------------------
# WebGUI is Copyright 2001-2009 Plain Black Corporation.
#-------------------------------------------------------------------
# Please read the legal notices (docs/legal.txt) and the license
# (docs/license.txt) that came with this distribution before using
# this software.
#-------------------------------------------------------------------
# http://www.plainblack.com                     info@plainblack.com
#-------------------------------------------------------------------

use strict;
use Time::HiRes;
use WebGUI::Asset;
use WebGUI::International;

=head1 NAME

Package WebGUI::Macro::AssetProxy

=head1 DESCRIPTION

Macro for displaying the output of an Asset in another location.

=head2 process ( url | assetId, [ type ] )

=head3 url | assetId

Specify either the asset url or the asset id. If no Asset with that URL or id can be found, an internationalized error message will be returned instead.

Editing controls (toolbar) may or may not be displayed in the Asset output, even if Admin is turned on.

The Not Found Page may not be Asset Proxied.

=head3 type

Defaults to 'url'. But if you want to use an assetId as the first parameter, then this parameter must be 'assetId'.

=cut

#-------------------------------------------------------------------
sub process {
    my ($session, $identifier, $type) = @_;
    if (!$identifier) {
        $session->errorHandler->warn('AssetProxy macro called without an asset to proxy. ' 
        . 'The macro was called through this url: '.$session->url->page);
        if ($session->var->isAdminOn) {
            my $i18n = WebGUI::International->new($session, 'Macro_AssetProxy');
            return $i18n->get('invalid url');
        }
        return;
    }
    my $t = ($session->errorHandler->canShowPerformanceIndicators()) ? [Time::HiRes::gettimeofday()] : undef;
    my $asset;
    if ($type eq 'assetId') {
        $asset = WebGUI::Asset->newByDynamicClass($session, $identifier);
    }
    else {
        $asset = WebGUI::Asset->newByUrl($session,$identifier);
    }
    if (!defined $asset) {
        $session->errorHandler->warn('AssetProxy macro called invalid asset: '.$identifier
            .'. The macro was called through this url: '.$session->url->page);
        if ($session->var->isAdminOn) {
            my $i18n = WebGUI::International->new($session, 'Macro_AssetProxy');
            return $i18n->get('invalid url');
        }
    }
    elsif ($asset->get('state') =~ /^trash/) {
        $session->errorHandler->warn('AssetProxy macro called on asset in trash: '.$identifier
            .'. The macro was called through this url: '.$session->url->page);
        if ($session->var->isAdminOn) {
            my $i18n = WebGUI::International->new($session, 'Macro_AssetProxy');
            return $i18n->get('asset in trash');
        }
    }
    elsif ($asset->get('state') =~ /^clipboard/) {
        $session->errorHandler->warn('AssetProxy macro called on asset in clipboard: '.$identifier
            .'. The macro was called through this url: '.$session->url->page);
        if ($session->var->isAdminOn) {
            my $i18n = WebGUI::International->new($session, 'Macro_AssetProxy');
            return $i18n->get('asset in clipboard');
        }
    }
    elsif ($asset->canView) {
        $asset->toggleToolbar;
        $asset->prepareView;
        my $output = $asset->view;
        $output .= "AssetProxy:" . Time::HiRes::tv_interval($t)
            if $t;
        return $output;
    }
    return '';
}


1;


