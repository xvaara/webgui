package WebGUI::Asset;

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

=head1 NAME

Package WebGUI::Asset (AssetClipboard)

=head1 DESCRIPTION

This is a mixin package for WebGUI::Asset that contains all clipboard related functions.

=head1 SYNOPSIS

 use WebGUI::Asset;


=head1 METHODS

These methods are available from this class:

=cut

#-------------------------------------------------------------------

=head2 canPaste ( )

Allows assets to have a say if they can be pasted.  For example, it makes no sense to
paste a wiki page anywhere else but a wiki master.

=cut

sub canPaste {
    my $self = shift;
    return $self->validParent($self->session);  ##Lazy call to a class method
}

#-------------------------------------------------------------------

=head2 copyInFork ( $process, $args )

WebGUI::Fork method called by www_copy

=cut

sub copyInFork {
    my ($process, $args) = @_;
    my $session = $process->session;
    my $asset = WebGUI::Asset->new($session, $args->{assetId});
    my @pedigree = ('self');
    my $childrenOnly = 0;
    if ($args->{childrenOnly}) {
        $childrenOnly = 1;
        push @pedigree, 'children';
    }
    else {
        push @pedigree, 'descendants';
    }
    my $ids   = $asset->getLineage(\@pedigree);
    my $tree  = WebGUI::ProgressTree->new($session, $ids);
    $process->update(sub { $tree->json });
    my $patch = Monkey::Patch::patch_class(
        'WebGUI::Asset', 'duplicate', sub {
            my $duplicate = shift;
            my $self      = shift;
            my $id        = $self->getId;
            $tree->focus($id);
            my $asset     = eval { $self->$duplicate(@_) };
            my $e         = $@;
            if ($e) {
                $tree->note($id, $e);
                $tree->failure($id, 'Died');
            }
            else {
                $tree->success($id);
            }
            $process->update(sub { $tree->json });
            die $e if $e;
            return $asset;
        }
    );
    my $newAsset = $asset->duplicateBranch($childrenOnly, 'clipboard');
    $newAsset->update({ title => $newAsset->getTitle . ' (copy)'});
    if ($args->{commit}) {
        my $tag = WebGUI::VersionTag->getWorking($session);
        $tag->requestCommit();
    }
}


#-------------------------------------------------------------------

=head2 cut ( )

Removes asset from lineage, places it in clipboard state. The "gap" in the lineage is changed in state to clipboard-limbo.
Return 1 if the cut was successful, otherwise it returns undef.

=cut

sub cut {
	my $self    = shift;
    my $session = $self->session;
	return undef if ($self->getId eq $session->setting->get("defaultPage") || $self->getId eq $session->setting->get("notFoundPage"));
	$session->db->beginTransaction;
	$session->db->write("update asset set state='clipboard-limbo' where lineage like ? and state='published'",[$self->get("lineage").'%']);
	$session->db->write("update asset set state='clipboard', stateChangedBy=?, stateChanged=? where assetId=?", [$session->user->userId, time(), $self->getId]);
	$session->db->commit;
	$self->{_properties}{state} = "clipboard";
    my $assetIter = $self->getLineageIterator(['descendants']);
    while ( 1 ) {
        my $asset;
        eval { $asset = $assetIter->() };
        if ( my $x = WebGUI::Error->caught('WebGUI::Error::ObjectNotFound') ) {
            $session->log->error($x->full_message);
            next;
        }
        last unless $asset;
        $asset->purgeCache;
        $asset->updateHistory('cut');
    }
    return 1;
}
 

#-------------------------------------------------------------------

=head2 duplicate ( [ options ] )

Duplicates this asset, returning the new asset.

=head3 options

A hash reference of options that can modify how this method works.

=head4 skipAutoCommitWorkflows

Assets that normally autocommit their workflows (like CS Posts, and Wiki Pages) won't if this is true.

=head4 skipNotification

Disable sending a notification that a new revision was added, for those assets that support it.

=head4 state

A state for the duplicated asset (defaults to 'published')

=cut

sub duplicate {
    my $self        = shift;
    my $options     = shift;
    my $parent      = $self->getParent;
    ##Remove state and pass all other options along to addChild
    my $asset_state = delete $options->{state};
    my $newAsset    
        = $parent->addChild(
            $self->get,
            undef,
            $self->get("revisionDate"),
            $options,
        );

    if (! $newAsset) {
        $self->session->log->error(
            sprintf "Unable to add child %s (%s) to %s (%s)", $self->getTitle, $self->getId, $parent->getTitle, $parent->getId
        );
        return undef;
    }
    # Duplicate metadata fields
    my $sth = $self->session->db->read(
        "select * from metaData_values where assetId = ? and revisionDate = ?",
        [$self->getId, $self->get('revisionDate')]
    );
    while (my $h = $sth->hashRef) {
        $self->session->db->write("insert into metaData_values (fieldId,
            assetId, revisionDate, value) values (?, ?, ?, ?)", [$h->{fieldId}, $newAsset->getId, $newAsset->get('revisionDate'), $h->{value}]);
    }

    # Duplicate keywords
    my $k = WebGUI::Keyword->new( $self->session );
    my $keywords    = $k->getKeywordsForAsset( {
        asset       => $self,
        asArrayRef  => 1,
    } );
    $k->setKeywordsForAsset( {
        asset       => $newAsset,
        keywords    => $keywords,
    } );

    if ($asset_state) {
        $newAsset->setState($asset_state);
    }

    return $newAsset;
}


#-------------------------------------------------------------------

=head2 getAssetsInClipboard ( [limitToUser,userId,expireTime] )

Returns an array reference of assets that are in the clipboard.  Only assets that are committed
or that are under the current user's version tag are returned.

=head3 limitToUser

If True, only return assets last updated by userId, specified below.

=head3 userId

If not specified, uses current user.

=head3 expireTime

If defined, then uses expireTime to limit returned assets to only include those
before expireTime.

=cut

sub getAssetsInClipboard {
	my $self = shift;
    my $session = $self->session;
	my $limitToUser = shift;
	my $userId = shift || $session->user->userId;
    my $expireTime = shift;

    my @limits = ();
	if ($limitToUser) {
		push @limits,  "asset.stateChangedBy=".$session->db->quote($userId);
	}
    if (defined $expireTime) {
		push @limits,  "stateChanged < ".$expireTime;
    }

    my $limit = join ' and ', @limits;

    my $root = WebGUI::Asset->getRoot($self->session);
    return $root->getLineage(
       ["descendants", ],
       {
           statesToInclude => ["clipboard"],
           returnObjects   => 1,
           statusToInclude => [qw/approved pending archived/],
           whereClause     => $limit,
       }
    );
}

#-------------------------------------------------------------------

=head2 paste ( assetId , [ outputSub ] )

Returns 1 if can paste an asset to a Parent. Sets the Asset to published. Otherwise returns 0.

=head3 assetId

Alphanumeric ID tag of Asset.

=head3 outputSub

A reference to a subroutine that output messages should be sent to.

=cut

sub paste {
	my $self         = shift;
	my $assetId      = shift;
    my $outputSub    = shift;
    my $session      = $self->session;
	my $pastedAsset  = WebGUI::Asset->newByDynamicClass($session,$assetId);
	return 0 unless ($self->get("state") eq "published");
    return 0 unless ($pastedAsset->canPaste());  ##Allow pasted assets to have a say about pasting.

    # Don't allow a shortcut to create an endless loop
    ##Do not paste a shortcut immediately below the original asset
    return 0 if $pastedAsset->isa('WebGUI::Asset::Shortcut') && $pastedAsset->get("shortcutToAssetId") eq $self->getId;
    my $i18n=WebGUI::International->new($session, 'Asset');
    $outputSub->(sprintf $i18n->get('pasting %s'), $pastedAsset->getTitle) if defined $outputSub;
	if ($self->getId eq $pastedAsset->get("parentId") || $pastedAsset->setParent($self)) {
        # Update lineage in search index.
        my $assetIter = $pastedAsset->getLineageIterator(
            ['self', 'descendants'], {
                statesToInclude => ['clipboard','clipboard-limbo']
            }
        );
        while ( 1 ) {
            my $asset;
            eval { $asset = $assetIter->() };
            if ( my $x = WebGUI::Error->caught('WebGUI::Error::ObjectNotFound') ) {
                $session->log->error($x->full_message);
                next;
            }
            last unless $asset;
 
            $outputSub->(sprintf $i18n->get('indexing %s'), $pastedAsset->getTitle) if defined $outputSub;
            $asset->setState('published');
            $asset->indexContent();
        }
		$pastedAsset->updateHistory("pasted to parent ".$self->getId);
		return 1;
	}
        
    return 0;
}

#-------------------------------------------------------------------

=head2 pasteInFork ( )

WebGUI::Fork method called by www_pasteList

=cut

sub pasteInFork {
    my ( $process, $args ) = @_;
    my $session = $process->session;
    my $self    = WebGUI::Asset->new( $session, $args->{assetId} );
    $session->asset( $self );
    my @roots   = grep { $_ && $_->canEdit }
        map { WebGUI::Asset->newPending( $session, $_ ) } @{ $args->{list} };

    my @ids = map {
        my $list
            = $_->getLineage( [ 'self', 'descendants' ], { statesToInclude => [ 'clipboard', 'clipboard-limbo' ] } );
        @$list;
    } @roots;

    my $tree = WebGUI::ProgressTree->new( $session, \@ids );
    $process->update(sub { $tree->json });
    my $patch = Monkey::Patch::patch_class(
        'WebGUI::Asset',
        'indexContent',
        sub {
            my $indexContent = shift;
            my $self         = shift;
            my $id           = $self->getId;
            $tree->focus($id);
            my $ret = eval { $self->$indexContent(@_) };
            my $e = $@;
            if ($e) {
                $tree->note( $id, $e );
                $tree->failure( $id, 'Died' );
            }
            else {
                $tree->success($id);
            }
            $process->update( sub { $tree->json } );
            die $e if $e;
            return $ret;
        }
    );
    $self->paste( $_->getId ) for @roots;
} ## end sub pasteInFork


#-------------------------------------------------------------------

=head2 www_copy ( )

Duplicates self, cuts duplicate, returns self->getContainer->www_view if
canEdit. Otherwise returns an AdminConsole rendered as insufficient privilege.
If with children/descendants is selected, a progress bar will be rendered.

=cut

sub www_copy {
    my $self    = shift;
    my $session = $self->session;
    my $http    = $session->http;
    my $redir   = $self->getParent->getUrl;
    return $session->privilege->insufficient unless $self->canEdit;

    my $with = $session->form->get('with');
    my %args;
    if ($with eq 'children') {
        $args{childrenOnly} = 1;
    }
    elsif ($with ne 'descendants') {
        my $newAsset = $self->duplicate({
                skipAutoCommitWorkflows => 1,
                state                   => 'clipboard'
            }
        );
        $newAsset->update({ title => $newAsset->getTitle . ' (copy)'});
        my $result = WebGUI::VersionTag->autoCommitWorkingIfEnabled(
            $session, {
                allowComments => 1,
                returnUrl     => $redir,
            }
        );
        $http->setRedirect($redir) unless $result eq 'redirect';
        return 'redirect';
    }

    my $tag = WebGUI::VersionTag->getWorking($session);
    if ($tag->canAutoCommit) {
        $args{commit} = 1;
        unless ($session->setting->get('skipCommitComments')) {
            $redir = $tag->autoCommitUrl($redir);
        }
    }

    $args{assetId} = $self->getId;
    $self->forkWithStatusPage({
            plugin   => 'ProgressTree',
            title    => 'Copy Assets',
            redirect => $redir,
            method   => 'copyInFork',
            args     => \%args
        }
    );
}

#-------------------------------------------------------------------

=head2 www_copyList ( )


Checks to see if the current user canEdit the parent containting the assets that
are being copied.  If that's not true, or if the CSRF token is missing, then
return insufficient privileges.

Copies the list of assets in the C<assetId> form variable, checking each one for edit privileges.

Returns the user to either the screen set by the C<proceed> form variable, or to
the Asset Manager.

=cut

sub www_copyList {
	my $self    = shift;
    my $session = $self->session;
	return $self->session->privilege->insufficient() unless $self->canEdit && $session->form->validToken;
	foreach my $assetId ($session->form->param("assetId")) {
		my $asset = WebGUI::Asset->newByDynamicClass($session,$assetId);
		if ($asset->canEdit) {
			my $newAsset = $asset->duplicate({skipAutoCommitWorkflows => 1, state => 'clipboard'});
			$newAsset->update({ title=>$newAsset->getTitle.' (copy)'});
		}
	}
	if ($self->session->form->process("proceed") ne "") {
                my $method = "www_".$session->form->process("proceed");
                return $self->$method();
        }
	return $self->www_manageAssets();
}

#-------------------------------------------------------------------

=head2 www_createShortcut ( )

=cut

sub www_createShortcut {
	my $self    = shift;
    my $session = $self->session;
    return $session->privilege->insufficient() if ! $self->canEdit;
	my $isOnDashboard = $self->getParent->isa('WebGUI::Asset::Wobject::Dashboard');

	my $shortcutParent = $isOnDashboard? $self->getParent : WebGUI::Asset->getImportNode($session);
	my $child = $shortcutParent->addChild({
		className=>'WebGUI::Asset::Shortcut',
		shortcutToAssetId=>$self->getId,
		title=>$self->getTitle,
		menuTitle=>$self->getMenuTitle,
		isHidden=>$self->get("isHidden"),
		newWindow=>$self->get("newWindow"),
		ownerUserId=>$self->get("ownerUserId"),
		groupIdEdit=>$self->get("groupIdEdit"),
		groupIdView=>$self->get("groupIdView"),
		url=>$self->get("title"),
		templateId=>'PBtmpl0000000000000140'
	});

    if (! $isOnDashboard) {
        $child->cut;
    }
    if (WebGUI::VersionTag->autoCommitWorkingIfEnabled($session, {
        allowComments   => 1,
        returnUrl       => $self->getUrl,
    }) eq 'redirect') {
        return 'redirect';
    };

    if ($isOnDashboard) {
		return $self->getParent->www_view;
	} else {
		$self->session->asset($self->getContainer);
		return $self->session->asset->www_manageAssets if ($self->session->form->process("proceed") eq "manageAssets");
		return $self->session->asset->www_view;
	}
}

#-------------------------------------------------------------------

=head2 www_cut ( )

If the current user canEdit, it puts $self into the clipboard and calls www_view on it's container.
Otherwise returns AdminConsole rendered insufficient privilege.

=cut

sub www_cut {
	my $self = shift;
	return $self->session->privilege->insufficient() unless $self->canEdit;
    return $self->session->privilege->vitalComponent
        if $self->get('isSystem');
	$self->cut;
    my $asset = $self->getContainer;
    if ($self->getId eq $asset->getId) {
        $asset = $self->getParent;
    }
	$self->session->asset($asset);
	return $asset->www_view;


}

#-------------------------------------------------------------------

=head2 www_cutList ( )

Checks to see if the current user canEdit the parent containting the assets that
are being cut.  If that's not true, or if the CSRF token is missing, then
return insufficient privileges.

Cuts the list of assets in the C<assetId> form variable, checking each one for edit privileges
and to see if it's a system asset.

Returns the user to either the screen set by the C<proceed> form variable, or to
the Asset Manager.

=cut

sub www_cutList {
	my $self = shift;
    my $session = $self->session;
	return $session->privilege->insufficient() unless $self->canEdit && $session->form->validToken;
	foreach my $assetId ($session->form->param("assetId")) {
		my $asset = WebGUI::Asset->newByDynamicClass($session,$assetId);
		if ($asset->canEdit && !$asset->get('isSystem')) {
			$asset->cut;
		}
	}
	if ($session->form->process("proceed") ne "") {
                my $method = "www_".$session->form->process("proceed");
                return $self->$method();
        }
	return $self->www_manageAssets();
}

#-------------------------------------------------------------------

=head2 www_duplicateList ( )

Checks to see if the current user canEdit the parent containting the assets that
are being duplicated.  If that's not true, or if the CSRF token is missing, then
return insufficient privileges.

Duplicates (copy and paste immediately) the list of assets in the C<assetId>
form variable, checking each one for edit privileges.

Returns the user to either the screen set by the C<proceed> form variable, or to
the Asset Manager.

=cut

sub www_duplicateList {
	my $self    = shift;
	my $session = $self->session;
	return $session->privilege->insufficient() unless $self->canEdit && $session->form->validToken;
	foreach my $assetId ($session->form->param("assetId")) {
		my $asset = WebGUI::Asset->newByDynamicClass($session,$assetId);
		if ($asset->canEdit) {
			my $newAsset = $asset->duplicate({skipAutoCommitWorkflows => 1});
			$newAsset->update({ title=>$newAsset->getTitle.' (copy)'});
		}
	}
	if ($session->form->process("proceed") ne "") {
                my $method = "www_".$session->form->process("proceed");
                return $self->$method();
        }
	return $self->www_manageAssets();
}

#-------------------------------------------------------------------

=head2 www_emptyClipboard ( )

Moves assets in clipboard to trash. Returns www_manageClipboard() when finished. If isInGroup(4) returns False, insufficient privilege is rendered.

=cut

sub www_emptyClipboard {
	my $self = shift;
	my $ac = WebGUI::AdminConsole->new($self->session,"clipboard");
	return $self->session->privilege->insufficient() unless ($self->session->user->isInGroup(4));
	foreach my $asset (@{$self->getAssetsInClipboard(!($self->session->form->process("systemClipboard") && $self->session->user->isInGroup($self->session->setting->get('groupIdAdminClipboard'))))}) {
		$asset->trash;
	}
	return $self->www_manageClipboard();
}


#-------------------------------------------------------------------

=head2 www_manageClipboard ( )

Returns an AdminConsole to deal with assets in the Clipboard. If isInGroup(12) is False, renders an insufficient privilege page.

=cut

sub www_manageClipboard {
	my $self = shift;
	my $ac = WebGUI::AdminConsole->new($self->session,"clipboard");
	return $self->session->privilege->insufficient() unless ($self->session->user->isInGroup(12));
	my $i18n = WebGUI::International->new($self->session, "Asset");

    my $header;
    my $limit = 1;

    my $canAdmin = $self->session->user->isInGroup($self->session->setting->get('groupIdAdminClipboard'));
    if ($self->session->form->process("systemClipboard") && $canAdmin) {
        $header = $i18n->get(966);
        $ac->addSubmenuItem($self->getUrl('func=manageClipboard'), $i18n->get(949));
        $ac->addSubmenuItem($self->getUrl('func=emptyClipboard;systemClipboard=1'), $i18n->get(959), 
            'onclick="return window.confirm(\''.$i18n->get(951,"WebGUI").'\')"',"Asset");
        $limit = undef;
    }
    elsif ( $canAdmin ) {
        $ac->addSubmenuItem($self->getUrl('func=manageClipboard;systemClipboard=1'), $i18n->get(954));
        $ac->addSubmenuItem($self->getUrl('func=emptyClipboard'), $i18n->get(950),
            'onclick="return window.confirm(\''.$i18n->get(951,"WebGUI").'\')"',"Asset");
    }
    else {
        $ac->addSubmenuItem($self->getUrl('func=emptyClipboard'), $i18n->get(950),
            'onclick="return window.confirm(\''.$i18n->get(951,"WebGUI").'\')"',"Asset");
    }
    $self->session->style->setLink($self->session->url->extras('assetManager/assetManager.css'), {rel=>"stylesheet",type=>"text/css"});
    $self->session->style->setScript($self->session->url->extras('assetManager/assetManager.js'), {type=>"text/javascript"});
        my $output = "
   <script type=\"text/javascript\">
   //<![CDATA[
     var assetManager = new AssetManager();
         assetManager.AddColumn('".WebGUI::Form::checkbox($self->session,{name=>"checkAllAssetIds", extras=>'onclick="toggleAssetListSelectAll(this.form);"'})."','','center','form');
         assetManager.AddColumn('".$i18n->get("99")."','','left','');
         assetManager.AddColumn('".$i18n->get("type")."','','left','');
         assetManager.AddColumn('".$i18n->get("last updated")."','','center','');
         assetManager.AddColumn('".$i18n->get("size")."','','right','');
         \n";
        foreach my $child (@{$self->getAssetsInClipboard($limit)}) {
		my $title = $child->getTitle;
		my $plus = $child->getChildCount({includeTrash => 1}) ? "+ " : "&nbsp;&nbsp;&nbsp;&nbsp;";
                $title =~ s/\'/\\\'/g;
                $output .= "assetManager.AddLine('"
                        .WebGUI::Form::checkbox($self->session,{
                                name=>'assetId',
                                value=>$child->getId
                                })
                        ."','" . $plus . "<a href=\"".$child->getUrl("op=assetManager")."\">" . $title
                        ."</a>','<p style=\"display:inline;vertical-align:middle;\"><img src=\"".$child->getIcon(1)."\" style=\"border-style:none;vertical-align:middle;\" alt=\"".$child->getName."\" /></p> ".$child->getName
                        ."','".$self->session->datetime->epochToHuman($child->get("revisionDate"))
                        ."','".formatBytes($child->get("assetSize"))."');\n";
                $output .= "assetManager.AddLineSortData('','".$title."','".$child->getName
                        ."','".$child->get("revisionDate")."','".$child->get("assetSize")."');\n";
        }
        $output .= '
            assetManager.AddButton("'.$i18n->get("delete").'","deleteList","manageClipboard");
            assetManager.AddButton("'.$i18n->get("restore").'","restoreList","manageClipboard");
            assetManager.AddFormHidden({ name:"webguiCsrfToken", value:"'.$self->session->scratch->get('webguiCsrfToken').'"});
                assetManager.Write();        
                var assetListSelectAllToggle = false;
                function toggleAssetListSelectAll(form) {
                    assetListSelectAllToggle = assetListSelectAllToggle ? false : true;
                    if (typeof form.assetId.length == "undefined") {
                        form.assetId.checked = assetListSelectAllToggle;
                    }
                    else {
                        for (var i = 0; i < form.assetId.length; i++)
                            form.assetId[i].checked = assetListSelectAllToggle;
                    }
                }
		 //]]>
                </script> <div class="adminConsoleSpacer"> &nbsp;</div>';
	return $ac->render($output, $header);
}


#-------------------------------------------------------------------

=head2 www_paste ( )

THIS METHOD IS DEPRECATED 6/18/2009.  It is replaced with www_pasteList.  It will be removed in WebGUI 8.

Returns "". Pastes an asset. If canEdit is False, returns an insufficient privileges page.

=cut

sub www_paste {
    my $self    = shift;
    my $session = $self->session;
    return $session->privilege->insufficient() unless $self->canEdit;
    my $pasteAssetId = $session->form->process('assetId');
    my $pasteAsset   = WebGUI::Asset->newPending($session, $pasteAssetId);
    return $session->privilege->insufficient() unless $pasteAsset && $pasteAsset->canEdit;
    $self->paste($pasteAssetId);
    return "";
}

#-------------------------------------------------------------------

=head2 www_pasteList ( )

Checks to see if the current user canEdit the parent containting the assets that
are being pasted.  If that's not true, or if the CSRF token is missing, then
return insufficient privileges.

Pastes the list of assets in the C<assetId> form variable, checking each one for edit privileges.

Returns the user to either the screen set by the C<proceed> form variable, or to
the Asset Manager.

=cut

sub www_pasteList {
    my $self    = shift;
    my $session = $self->session;
    my $form    = $session->form;
    return $session->privilege->insufficient() unless $self->canEdit && $session->form->validToken;

    $self->forkWithStatusPage( {
            plugin   => 'ProgressTree',
            title    => 'Paste Assets',
            redirect => $self->getUrl(
                $form->get('proceed') eq 'manageAssets'
                ? 'op=assetManager'
                : ()
            ),
            method => 'pasteInFork',
            args   => {
                assetId => $self->getId,
                list    => [ $form->get('assetId') ],
            }
        }
    );
} ## end sub www_pasteList

1;

