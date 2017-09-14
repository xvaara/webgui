package WebGUI::Asset::Wobject::GalleryAlbum;

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
use base qw(WebGUI::AssetAspect::RssFeed WebGUI::Asset::Wobject);


use Class::C3;
use Carp qw( croak );
use File::Find;
use File::Spec;
use File::Temp qw{ tempdir };
use Image::ExifTool qw( :Public );
use JSON;
use Tie::IxHash;

use WebGUI::International;
use WebGUI::Utility;
use WebGUI::HTML;
use WebGUI::ProgressBar;
use WebGUI::Storage;

# Do not move this instruction!
use Archive::Any;

=head1 NAME

=head1 DESCRIPTION

=head1 SYNOPSIS

=head1 DIAGNOSTICS

=head1 METHODS

=cut

#-------------------------------------------------------------------

=head2 definition ( )

Define wobject properties for new GalleryAlbum wobjects.

=cut

sub definition {
    my $class       = shift;
    my $session     = shift;
    my $definition  = shift;
    my $i18n        = WebGUI::International->new($session, 'Asset_GalleryAlbum');

    tie my %properties, 'Tie::IxHash', (
        allowComments   => {
            fieldType       => "yesNo",
            defaultValue    => 1,
        },
        othersCanAdd    => {
            fieldType       => "yesNo",
            defaultValue    => 0,
        },
        assetIdThumbnail => {
            fieldType       => "asset",
            defaultValue    => undef,
        },
    );

    # UserDefined Fields
    for my $i (1 .. 5) {
        $properties{"userDefined".$i} = {
            defaultValue        => undef,
        };
    }

    push @{$definition}, {
        assetName           => $i18n->get('assetName'),
        autoGenerateForms   => 0,
        icon                => 'photoAlbum.gif',
        tableName           => 'GalleryAlbum',
        className           => __PACKAGE__,
        properties          => \%properties,
    };

    return $class->next::method($session, $definition);
}

#----------------------------------------------------------------------------

=head2 addArchive ( filename, properties, [$outputSub] )

Add an archive of Files to this Album. C<filename> is the full path of the 
archive. C<properties> is a hash reference of properties to assign to the
photos in the archive.

Will croak if cannot read the archive or if the archive will extract itself to
a directory outside of the storage location.

Will only handle file types handled by the parent Gallery.

=head3 filename

The name of the file archive to import.

=head3 properties

A base set of properties to add to each file in the archive.

=head3 sortBy

Order in which files should be added to the gallery album. Legal values are 
'name', 'date' and 'fileOrder'. If missing or invalid, files will be added as 
ordered in the archive (default; corresponding to 'fileOrder').

=head3 $outputSub

A callback to use for outputting data, most likely to a progress bar.  It expects the
callback to accept an i18n key for use in sprintf, and then any extra fields to stuff
into the translated key.

=cut

sub addArchive {
    my $self        = shift;
    my $filename    = shift;
    my $properties  = shift;
    my $sortBy      = shift;
    my $outputSub   = shift || sub {};
    my $gallery     = $self->getParent;
    my $session     = $self->session;
    
    my $archive     = Archive::Any->new( $filename );

    die "Archive will extract to directory outside of storage location!\n"
        if $archive->is_naughty;

    my $tempdirName = tempdir( "WebGUI-Gallery-XXXXXXXX", TMPDIR => 1, CLEANUP => 1);
    $outputSub->('Extracting archive');
    $archive->extract( $tempdirName );

    # Get all the files in the archive
    $outputSub->('Getting list of files for sorting purposes');
    my @files = map { File::Spec->catfile($tempdirName, $_); } $archive->files;

    # Sort files by date
    if ($sortBy eq 'date') {              
        # Hash for storing last modified timestamps
        my %mtimes;        
    
        my $exifTool = Image::ExifTool->new;
        # Make ExifTool return epoch timestamps
        $exifTool->Options('DateFormat', '%s');

        # Iterate through all files
        foreach my $file (@files) {            
            # Extract exif data from image
            $exifTool->ExtractInfo( $file );
            # Get last modified timestamp from exif data
            $mtimes{$file} = $exifTool->GetValue('ModifyDate');
            # Use last modified date of file as fallback
            $mtimes{$file} = (stat($file))[9] unless $mtimes{$file};
        }
        
        # Sort files based on last modified timestamps
        @files = sort { $mtimes{$a} <=> $mtimes{$b} } @files;
    } 
    # Sort files by name
    elsif ($sortBy eq 'name') {
        @files = sort @files;
    }

    for my $filePath (@files) {
        my ($volume, $directory, $filename) = File::Spec->splitpath( $filePath );
        next unless $filename;
        next if $filename =~ m{^[.]};
        next if $filename =~ m{^thumb-};
        my $class       = $gallery->getAssetClassForFile( $filePath );
        next unless $class; # class is undef for those files the Gallery can't handle

        $session->errorHandler->info( "Adding $filename to album!" );
        $outputSub->('Adding %s to album', $filename);
        # Remove the file extension
        $filename   =~ s{\.[^.]+}{};

        $properties->{ className        } = $class;
        $properties->{ menuTitle        } = $filename;
        $properties->{ title            } = $filename;
        $properties->{ ownerUserId      } = $session->user->userId;
        $properties->{ url              } = $session->url->urlize( $self->getUrl . "/" . $filename );

        my $asset   = $self->addChild( $properties, undef, undef, { skipAutoCommitWorkflows => 1 } );
        $asset->setFile( $filePath );
    }

    my $versionTag      = WebGUI::VersionTag->getWorking( $session );
    $versionTag->set({ 
        "workflowId" => $self->getParent->get("workflowIdCommit"),
    });
    $outputSub->('Requesting commit for version tag');
    $versionTag->requestCommit;

    return undef;
}

#----------------------------------------------------------------------------

=head2 appendTemplateVarsFileLoop ( vars, assetIds )

Append template vars for a file loop for the specified assetIds. C<vars> is
a hash reference to add the file loop to. C<assetIds> is an array reference
of assetIds for the loop.

Returns the hash reference for convenience.

=cut

sub appendTemplateVarsFileLoop {
    my $self        = shift;
    my $var         = shift;
    my $assetIds    = shift;
    my $session     = $self->session;

    ASSET: for my $assetId (@$assetIds) {
        my $asset = WebGUI::Asset->newByDynamicClass($session, $assetId);
        next ASSET unless $asset;
        # Set the parent
        $asset->{_parent} = $self;
        push @{$var->{file_loop}}, $asset->getTemplateVars;
    }

    return $var;
}

#----------------------------------------------------------------------------

=head2 canAdd ( )

Override canAdd to ignore its permissions check. Permissions are handled
by the parent Gallery and other permissions methods.

=cut

sub canAdd {
    return 1;
}

#----------------------------------------------------------------------------

=head2 canAddFile ( [userId] )

Returns true if the user can add a file to this album. C<userId> is a WebGUI
user ID. If no userId is passed, will check the current user.

Users can add files to this album if they are the owner, if 
C<othersCanAdd> is true and the Gallery allows them to add files, or if
they are allowed to edit the parent Gallery.

=cut

sub canAddFile {
    my $self        = shift;
    my $userId      = shift || $self->session->user->userId;
    my $gallery     = $self->getParent;

    return 1 if $userId eq $self->get("ownerUserId");
    return 1 if $self->get("othersCanAdd") && $gallery->canAddFile( $userId );
    return $gallery->canEdit( $userId );
}

#----------------------------------------------------------------------------

=head2 canComment ( [userId] )

Returns true if the user is allowed to comment on files in this Album. 
C<userId> is a WebGUI user ID. If no userId is passed, will check the current
user.

Users can comment on files if C<allowComments> is true and the parent Gallery
allows comments.

=cut

sub canComment {
    my $self        = shift;
    my $userId      = shift || $self->session->user->userId;
    my $gallery     = $self->getParent;

    return 0 if !$self->get("allowComments");

    return $gallery->canComment( $userId );
}

#----------------------------------------------------------------------------

=head2 canEdit ( [userId] )

Returns true if the user can edit this asset. C<userId> is a WebGUI user ID. 
If no userId is passed, check the current user.

Users can edit this GalleryAlbum if they are the owner, or if they can edit
the Gallery parent.

Also handles adding of child assets by calling C<canAddFile>.

=cut

sub canEdit {
    my $self        = shift;
    my $userId      = shift || $self->session->user->userId;
    my $gallery     = $self->getParent;
    my $form        = $self->session->form;

    # Handle adding a photo
    if ( $form->get("func") eq "add" || $form->get("func") eq "editSave" ) {
        return $self->canAddFile;
    }
    else {
        return 1 if $userId eq $self->get("ownerUserId");
        return $gallery && $gallery->canEdit($userId);
    }
}

#----------------------------------------------------------------------------

=head2 canEditIfLocked ( [userId] )

Override this to allow editing when locked under a different version tag.

=cut

sub canEditIfLocked {
    my $self        = shift;
    my $userId      = shift;

    return $self->canEdit( $userId );
}

#----------------------------------------------------------------------------

=head2 canView ( [userId] )

Returns true if the user can view this asset. C<userId> is a WebGUI user ID.
If no userId is given, checks the current user.

Users can view this album if they can view the containing Gallery.

NOTE: It may be possible to view a GalleryAlbum that has no public files. In
such cases, the GalleryAlbum will appear empty to unprivileged users. This is 
not a bug.

=cut

sub canView {
    my $self        = shift;
    my $userId      = shift || $self->session->user->userId;
    return $self->getParent->canView($userId);
}

#----------------------------------------------------------------------------

=head2 DESTROY

Destroy the cached assets

=cut

sub DESTROY {
    my $self        = shift;
    for my $key ( qw/ _nextAlbum _prevAlbum / ) {
        my $asset       = delete $self->{ $key };
        $asset->DESTROY if $asset;
    }
}

#----------------------------------------------------------------------------

=head2 getAutoCommitWorkflowId ( )

Returns the workflowId of the Gallery's approval workflow.

=cut

sub getAutoCommitWorkflowId {
    my $self        = shift;
    my $gallery = $self->getParent;
    if ($gallery->hasBeenCommitted) {
        return $gallery->get("workflowIdCommit")
            || $self->session->setting->get('defaultVersionTagWorkflow');
    }
    return undef;
}

#----------------------------------------------------------------------------

=head2 getCurrentRevisionDate ( session, assetId )

Override this to allow instanciation of "pending" GalleryAlbums for those who
are authorized to see them.

=cut

sub getCurrentRevisionDate {
    my $class       = shift;
    my $session     = shift;
    my $assetId     = shift;

    # Get the highest revision date, instanciate the asset, and see if 
    # the permissions are enough to return the revisionDate.
    my $revisionDate
        = $session->db->quickScalar( 
            "SELECT MAX(revisionDate) FROM GalleryAlbum WHERE assetId=?",
            [ $assetId ]
        );

    return undef unless $revisionDate;

    my $asset   = WebGUI::Asset->new( $session, $assetId, $class, $revisionDate );

    return undef unless $asset;

    if ( $asset->get( 'status' ) eq "approved" || $asset->canEdit ) {
        return $revisionDate;
    }
    else {
        return $class->next::method( $session, $assetId );
    }
}

#----------------------------------------------------------------------------

=head2 getFileIds ( )

Gets an array reference of asset IDs for all the files in this album.

=cut

sub getFileIds {
    my $self        = shift;

    if ( !$self->session->stow->get( 'fileIds-' . $self->getId ) ) {
        my $gallery     = $self->getParent;
        
        # Deal with "pending" files.
        my %pendingRules;
        if ( $self->canEdit ) {
            $pendingRules{ statusToInclude } = [ 'pending', 'approved' ];
        }
        else {
            $pendingRules{ statusToInclude } = [ 'pending', 'approved' ];
            $pendingRules{ whereClause } = q{
                ( 
                    status = "approved" || ownerUserId = "} . $self->session->user->userId . q{"
                )
            };
        }
        
        $self->session->stow->set( 
            "fileIds-" . $self->getId, 
            $self->getLineage( ['descendants'], { (%pendingRules) } ),
        );
    }

    return $self->session->stow->get( "fileIds-" . $self->getId );
}

#----------------------------------------------------------------------------

=head2 getNextFileId ( fileId )

Gets the next fileId from the list of fileIds. C<fileId> is the base 
fileId we want to find the next file for.

Returns C<undef> if there is no next fileId.

=cut

sub getNextFileId {
    my $self       = shift;
    my $fileId     = shift;
    my $allFileIds = $self->getFileIds;

    while ( my $checkId = shift @{ $allFileIds } ) {
        # If this is the last albumId
        return undef unless @{ $allFileIds };

        if ( $fileId eq $checkId ) {
            return shift @{ $allFileIds };
        }
    }
}

#----------------------------------------------------------------------------

=head2 getPreviousFileId ( fileId )

Gets the previous fileId from the list of fileIds. C<fileId> is the base 
fileId we want to find the previous file for.

Returns C<undef> if there is no previous fileId.

=cut

sub getPreviousFileId {
    my $self       = shift;
    my $fileId     = shift;
    my $allFileIds = $self->getFileIds; 

    while ( my $checkId = pop @{ $allFileIds } ) {
        # If this is the last albumId
        return undef unless @{ $allFileIds };

        if ( $fileId eq $checkId ) {
            return pop @{ $allFileIds };
        }
    }
}

#----------------------------------------------------------------------------

=head2 getFilePaginator ( paginatorUrl )

Gets a WebGUI::Paginator for the files in this album. C<paginatorUrl> is the 
url to the current page that will be given to the paginator.

=cut

sub getFilePaginator {
    my $self        = shift;
    my $url         = shift     || $self->getUrl;
    my $perPage     = $self->getParent->get( 'defaultFilesPerPage' );

    my $p           = WebGUI::Paginator->new( $self->session, $url, $perPage );
    $p->setDataByArrayRef( $self->getFileIds );

    return $p;
}

#----------------------------------------------------------------------------

=head2 getNextAlbum ( ) 

Get the next album from the Gallery. Returns an instance of a GalleryAlbum,
or undef if there is no next album.

=cut

sub getNextAlbum {
    my $self        = shift;
    return $self->{_nextAlbum} if $self->{_nextAlbum};
    my $nextId      = $self->getParent->getNextAlbumId( $self->getId );
    return undef unless $nextId;
    $self->{_nextAlbum } = WebGUI::Asset->newByDynamicClass( $self->session, $nextId );
    return $self->{_nextAlbum};
}

#----------------------------------------------------------------------------

=head2 getPreviousAlbum ( ) 

Get the previous album from the Gallery. Returns an instance of a GalleryAlbum,
or undef if there is no previous album.

=cut

sub getPreviousAlbum {
    my $self        = shift;
    return $self->{_previousAlbum} if $self->{_previousAlbum};
    my $previousId  = $self->getParent->getPreviousAlbumId( $self->getId );
    return undef unless $previousId;
    $self->{_previousAlbum} = WebGUI::Asset->newByDynamicClass( $self->session, $previousId );
    return $self->{_previousAlbum};
}

#-------------------------------------------------------------------

=head2 getRssFeedItems ()

Returns an array reference of hash references. Each hash reference has a title,
description, link, and date field. The date field can be either an epoch date, an RFC 1123
date, or a ISO date in the format of YYYY-MM-DD HH:MM::SS. Optionally specify an
author, and a guid field.

=cut

sub getRssFeedItems {
    my $self        = shift;

    my $p
        = $self->getFilePaginator( { 
            perpage     => $self->get('itemsPerFeed'),
        } );
    
    my $var = [];
    for my $assetId ( @{ $p->getPageData } ) {
        my $asset       = WebGUI::Asset::Wobject::GalleryAlbum->newPending( $self->session, $assetId );
        push @{ $var }, {
            'link'          => $asset->getUrl,
            'guid'          => $asset->{_properties}->{ 'assetId' },
            'title'         => $asset->getTitle,
            'description'   => $asset->{_properties}->{ 'description' },
            'date'          => $asset->{_properties}->{ 'creationDate' },
            'author'        => WebGUI::User->new($self->session, $asset->{_properties}->{ 'ownerUserId' })->username
        };
    }
    
    return $var;
}

#----------------------------------------------------------------------------

=head2 getTemplateVars ( )

Gets template vars common to all views.

=cut

sub getTemplateVars {
    my $self        = shift;
    my $session     = $self->session;
    my $gallery     = $self->getParent;
    my $var         = $self->get;
    my $owner       = WebGUI::User->new( $session, $self->get("ownerUserId") );

    # Fix 'undef' vars since HTML::Template does inheritence on them
    for my $key ( qw( description ) ) {
        unless ( defined $var->{$key} ) {
            $var->{ $key } = '';
        }
    }    
 
    # Set a flag for pending files
    if ( $self->get( "status" ) eq "pending" ) {
        $var->{ 'isPending' } = 1;
    }

    # Permissions
    $var->{ canAddFile              } = $self->canAddFile;
    $var->{ canEdit                 } = $self->canEdit;
    
    # Add some common template vars from Gallery
    $gallery->appendTemplateVarsSearchForm( $var );
    $var->{ url_listAlbums              } = $gallery->getUrl('func=listAlbums');
    $var->{ url_listAlbumsRss           } = $gallery->getUrl('func=listAlbumsRss');
    $var->{ url_listFilesForCurrentUser } = $gallery->getUrl('func=listFilesForUser');
    $var->{ url_search                  } = $gallery->getUrl('func=search');

    # Add some specific vars from the Gallery
    my $galleryVar      = $gallery->getTemplateVars;
    for my $key ( qw{ title menuTitle url displayTitle } ) {
        $var->{ "gallery_" . $key } = $galleryVar->{ $key };
    }

    # Friendly URLs
    $var->{ url                     } = $self->getUrl;
    $var->{ url_addArchive          } = $self->getUrl('func=addArchive');
    $var->{ url_addPhoto            } = $self->getUrl("func=add;class=WebGUI::Asset::File::GalleryFile::Photo");
    $var->{ url_addNoClass          } = $self->getUrl("func=add");
    $var->{ url_delete              } = $self->getUrl("func=delete");
    $var->{ url_edit                } = $self->getUrl("func=edit");
    $var->{ url_listFilesForOwner   } = $gallery->getUrl("func=listFilesForUser;userId=".$var->{ownerUserId});
    $var->{ url_viewRss             } = $self->getUrl("func=viewRss");
    $var->{ url_slideshow           } = $self->getUrl("func=slideshow");
    $var->{ url_thumbnails          } = $self->getUrl("func=thumbnails");
    
    if ( my $nextAlbum  = $self->getNextAlbum ) {
        $var->{ nextAlbum_url           } = $nextAlbum->getUrl;
        $var->{ nextAlbum_title         } = $nextAlbum->get( "title" );
        $var->{ nextAlbum_thumbnailUrl  } = $nextAlbum->getThumbnailUrl;
    }
    if ( my $prevAlbum  = $self->getPreviousAlbum ) {
        $var->{ previousAlbum_url           } = $prevAlbum->getUrl;
        $var->{ previousAlbum_title         } = $prevAlbum->get( "title" );
        $var->{ previousAlbum_thumbnailUrl  } = $prevAlbum->getThumbnailUrl;
    }

    $var->{ fileCount               } = $self->getChildCount;
    $var->{ ownerUsername           } = $owner->username;
    $var->{ thumbnailUrl            } = $self->getThumbnailUrl;

    return $var;
}

#----------------------------------------------------------------------------

=head2 getThumbnailUrl ( )

Gets the URL for the thumbnail for this asset. If no asset is set, gets the 
first child.

NOTE: If the asset does not have a getThumbnailUrl method, this method will
return undef.

=cut

sub getThumbnailUrl {
    my $self        = shift;
    my $asset       = undef;
    
    # Try to get the asset
    if ( $self->get("assetIdThumbnail") ) {
        $asset      = WebGUI::Asset->newByDynamicClass( $self->session, $self->get("assetIdThumbnail") );
    }
    elsif ( $self->getFirstChild ) {
        $asset      = $self->getFirstChild;
    }
    else {
        return undef;
    }

    # It is possible to get here and still not have an asset in cases of
    # "pending" assets, so just return
    if ( !$asset ) {
        return undef;
    }
    
    # Get the URL for the asset's thumbnail
    if ( $asset->can("getThumbnailUrl") ) {
        return $asset->getThumbnailUrl;
    }
    elsif ( $asset->isa( "WebGUI::Asset::Shortcut" ) ) {
        return $asset->getShortcut->getThumbnailUrl;
    }
    else {
        return undef;
    }
}

#----------------------------------------------------------------------------

=head2 othersCanAdd ( )

Returns true if people other than the owner can add files to this album.

=cut

sub othersCanAdd {
    my $self        = shift;
    return $self->get("othersCanAdd");
}

#----------------------------------------------------------------------------

=head2 prepareView ( )

See WebGUI::Asset::prepareView() for details.

=cut

sub prepareView {
    my $self = shift;
    $self->next::method();

    my $templateId  = $self->getParent->get("templateIdViewAlbum");

    my $template 
        = WebGUI::Asset::Template->new($self->session, $templateId);
    if (!$template) {
        WebGUI::Error::ObjectNotFound::Template->throw(
            error      => qq{Template not found},
            templateId => $templateId,
            assetId    => $self->getId,
        );
    }
    $template->prepare($self->getMetaDataAsTemplateVariables);

    $self->{_viewTemplate}  = $template;
    $self->{_viewVariables} = $self->getTemplateVars;
}

#----------------------------------------------------------------------------

=head2 processFileSynopsis ( )

Process the synopsis for the files on the GalleryAlbum C<www_edit> page.

=cut

sub processFileSynopsis {
    my $self        = shift;
    my $session     = $self->session;
    my $form        = $self->session->form;
    
    # Do the version tag shuffle
    my $oldVersionTag   = WebGUI::VersionTag->getWorking( $session, "nocreate" );
    my $newVersionTag
        = WebGUI::VersionTag->create( $session, {
            workflowId      => $self->getParent->get("workflowIdCommit"),
        } );
    $newVersionTag->setWorking;
    
    for my $key ( grep { /^fileSynopsis_/ } $form->param ) {
        ( my $assetId ) = $key =~ /^fileSynopsis_(.+)$/;
        my $synopsis    = $form->get( $key );
    
        my $asset       = WebGUI::Asset->newByDynamicClass( $session, $assetId );
        if ( $asset->get("synopsis") ne $synopsis ) {
            my $properties  = $asset->get;
            $properties->{ synopsis } = $synopsis;

            $asset->addRevision( $properties, undef, { skipAutoCommitWorkflows => 1 } );
        }
    }
    
    # That's what it's all about
    $newVersionTag->commit;
    if ( $oldVersionTag ) {
        WebGUI::VersionTag->setWorking( $oldVersionTag );
    }

    return;
}

#----------------------------------------------------------------------------

=head2 processStyle ( )

Gets the parent Gallery's style template

=cut

sub processStyle {
    my $self        = shift;
    return $self->getParent->processStyle(@_);
}

#----------------------------------------------------------------------------

=head2 processPropertiesFromFormPost ( )

Process the form to save the asset. Request approval from the Gallery's 
approval workflow.

=cut

sub processPropertiesFromFormPost {
    my $self        = shift;
    my $form        = $self->session->form;
    my $errors      = $self->next::method || [];

    # Return if error
    return $errors  if @$errors;

    ### Passes all checks
}

#----------------------------------------------------------------------------

=head2 sendChunkedContent ( callback )

Send chunked content to the user. Will send the head of the style template, 
run the C<callback> to get the body content, then send the footer of the style
template.

=cut

sub sendChunkedContent {
    my $self        = shift;
    my $callback    = shift;

    my $session = $self->session;

	$session->http->setLastModified($self->getContentLastModified);
	$session->http->sendHeader;
	my $style = $self->processStyle($self->getSeparator);
	my ($head, $foot) = split($self->getSeparator,$style);
	$session->output->print($head, 1);
	$session->output->print( $callback->() );
	$session->output->print($foot, 1);
	return "chunked";
}

#----------------------------------------------------------------------------

=head2 update ( )

Override update to force isHidden=1 on all albums.

=cut

sub update {
    my $self        = shift;
    my $properties  = shift;
    return $self->next::method({ %{ $properties }, isHidden=>1 });
}

#----------------------------------------------------------------------------

=head2 view ( )

method called by the www_view method.  Returns a processed template
to be displayed within the page style.  

=cut

sub view {
    my $self        = shift;
    my $session     = $self->session;	
    my $var         = delete $self->{_viewVariables};
    
    my $p           = $self->getFilePaginator;
    $p->appendTemplateVars( $var );
    $self->appendTemplateVarsFileLoop( $var, $p->getPageData );

    return $self->processTemplate($var, undef, $self->{_viewTemplate});
}

#----------------------------------------------------------------------------

=head2 view_slideshow ( )

method called by the www_slideshow method. Returns a processed template to be
displayed within the page style.

Show a slideshow of the GalleryAlbum's files.

=cut

sub view_slideshow {
    my $self        = shift;
    my $session     = $self->session;	
    my $var         = delete $self->{_templateVars};
    return $self->processTemplate($var, $self->getParent->get("templateIdViewSlideshow"), $self->{_preparedTemplate});
}

#----------------------------------------------------------------------------

=head2 view_thumbnails ( )

method called by the www_thumbnails method. Returns a processed template to be
displayed within the page style.

Shows all the thumbnails for this GalleryAlbum. In addition, shows details 
about a specific thumbnail.

=cut

sub view_thumbnails {
    my $self        = shift;
    my $session     = $self->session;	
    my $var         = delete $self->{_templateVars};

    my $fileId      = $session->form->get("fileId");

    # Process the file loop to add an additional URL
    for my $file ( @{ $var->{file_loop} } ) {
        $file->{ url_albumViewThumbnails }
            = $self->getUrl('func=thumbnails;fileId=' . $file->{assetId});
    }

    # Add direct vars for the requested file
    my $asset;
    if ($fileId) {
        $asset  = WebGUI::Asset->newByDynamicClass( $session, $fileId );
    }
    # If no fileId given or fileId does not exist
    if (!$asset) {
        $asset  = $self->getFirstChild;
    }
    
    if ( $asset ) {
        my %assetVars   = %{ $asset->getTemplateVars };
        for my $key ( keys %assetVars ) {
            $var->{ 'file_' . $key } = $assetVars{ $key };
        }
    }

    return $self->processTemplate($var, $self->getParent->get("templateIdViewThumbnails"));
}

#----------------------------------------------------------------------------

=head2 www_addArchive ( params )

Show the form to add an archive of files to this gallery. C<params> is a hash
reference of parameters with the following keys:

 error          => An error message to show to the user.

=cut

sub www_addArchive {
    my $self        = shift;
    my $params      = shift;
    
    return $self->session->privilege->insufficient unless $self->canAddFile;

    my $session     = $self->session;
    my $form        = $self->session->form;
    my $var         = $self->getTemplateVars;

    my $i18n = WebGUI::International->new($session);

    $var->{ error           } = $params->{ error } || $form->get('error');

    $var->{ form_start      } 
        = WebGUI::Form::formHeader( $session, {
            action          => $self->getUrl('func=addArchiveSave'),
            name            => 'name="galleryAlbumAddArchive"',
        });
    $var->{ form_end        }
        = WebGUI::Form::formFooter( $session );

    $var->{ form_submit     } 
        = WebGUI::Form::submit( $session, {
            name            => "submit",
            value           => $i18n->get("submit",'WebGUI'),
        });

    $var->{ form_archive    } 
        = WebGUI::Form::File( $session, {
            name            => "archive",
            maxAttachments  => 1,
            value           => ( $form->get("archive") ),
        });

    $var->{ form_keywords   } 
        = WebGUI::Form::text( $session, {
            name            => "keywords",
            value           => ( $form->get("keywords") ),
        });
        
    $var->{ form_location   }
        = WebGUI::Form::Text( $session, {
            name            => "location",
            value           => ( $form->get("location") ),
        });        

    $var->{ form_friendsOnly }
        = WebGUI::Form::yesNo( $session, {
            name            => "friendsOnly",
            value           => ( $form->get("friendsOnly") ),
        });
        
    $var->{ form_sortBy     }
        = WebGUI::Form::RadioList( $session, {
            name            => "sortBy",
            value           => [ "name" ],
            options         => {
                name            => $i18n->get("addArchive sortBy name", 'Asset_GalleryAlbum'),                
                date            => $i18n->get("addArchive sortBy date", 'Asset_GalleryAlbum'),
                fileOrder       => $i18n->get("addArchive sortBy fileOrder", 'Asset_GalleryAlbum'),
            },
        });

    return $self->processStyle(
        $self->processTemplate($var, $self->getParent->get("templateIdAddArchive"))
    );
}

#-----------------------------------------------------------------------------

=head2 www_addArchiveSave ( )

Process the form for adding an archive.

=cut

sub www_addArchiveSave {
    my $self        = shift;

    # Return error message if the user viewing does not have permission to add files
    return $self->session->privilege->insufficient unless $self->canAddFile;

    my $session     = $self->session;
    my $form        = $self->session->form;
    my $i18n        = WebGUI::International->new( $session, 'Asset_GalleryAlbum' );
    my $pb          = WebGUI::ProgressBar->new($session);

    # Retrieve properties and sort order from form variables
    my $properties  = {
        keywords        => $form->get("keywords"),
        location        => $form->get("location"),
        friendsOnly     => $form->get("friendsOnly"),
    };
    my $sortBy = $form->get("sortBy");
    
    # Create progress bar to keep the connection alive
    $pb->start($i18n->get('Uploading archive'), $session->url->extras('adminConsole/assets.gif'));
    
    # Retrieve storage containing the uploaded archive
    my $storageId   = $form->get("archive", "File");
    my $storage     = WebGUI::Storage->get( $session, $storageId );
    if (!$storage) {
        return $pb->finish($self->getUrl('func=addArchive;error='.$i18n->get('addArchive error too big')));
    }

    # Get the full path to the archive
    my $filename    = $storage->getPath( $storage->getFiles->[0] );
    
    # Try to add files in archive as photos
    eval { $self->addArchive( $filename, $properties, $sortBy, sub{ $pb->update(sprintf $i18n->get(shift), @_); }); };
    
    # Delete storage containing archive
    $storage->delete;
    if ( my $error = $@ ) {
        return $pb->finish($self->getUrl('func=addArchive;error='.sprintf $i18n->get('addArchive error generic'), $error ));
    }

    return $pb->finish($self->getUrl);
}

#----------------------------------------------------------------------------

=head2 www_addFileService ( )

A web service to create files in albums. Returns a json string that looks like this:

    {
       "lastUpdated" : "2008-10-13 20:06:13",
       "thumbnailUrl" : "http://dev.localhost.localdomain/uploads/W1/X9/W1X9A95iagNbq4n1utdXug/thumb-jt_25.jpg",
       "url" : "http://dev.localhost.localdomain/cool-gallery/the-cool-album3/jt13",
       "title" : "JT",
       "dateCreated" : "2008-10-13 20:06:13"
    }

You can make the request as a post to the gallery url with the following variables:

=head3 func

Required. Must have a value of "addFileService"

=head3 as

Defaults to 'json', but if specified as 'xml' then the return result will be:

    <opt>
      <dateCreated>2008-10-13 20:08:18</dateCreated>
      <lastUpdated>2008-10-13 20:08:18</lastUpdated>
      <thumbnailUrl>http://dev.localhost.localdomain/uploads/1k/-B/1k-BTF8m4e6wmXJKRxraIA/thumb-jt_25.jpg</thumbnailUrl>
      <title>JT</title>
      <url>http://dev.localhost.localdomain/cool-gallery/the-cool-album3/jt14</url>
    </opt>

=head3 title

The title of the album you wish to create.

=head3 synopsis

A brief description of the album you wish to create.

=head3 file

A file attached to the multi-part post.

=cut

sub www_addFileService {
    my $self        = shift;
    my $session     = $self->session;
    
    return $session->privilege->insufficient unless ($self->canAddFile);
    my $form = $session->form;
    
    
    my $file = $self->addChild({
        className       => "WebGUI::Asset::File::GalleryFile::Photo",
        title           => $form->get('title','text'),
        description     => $form->get('synopsis','textarea'),
        synopsis        => $form->get('synopsis','textarea'),
        ownerUserId     => $session->user->userId,
    });

    my $storage = $file->getStorageLocation;
    my $filename = $storage->addFileFromFormPost('file');
    $file->setFile;
#  my $storageId =  $form->get('file','File');
#    my $filePath = $storage->getPath( $storage->getFiles->[0] );
 #   $self->setFile( $filePath );
  #  $storage->delete;
    #$session->log->warn('XX:'. $filename);
    
    $file->requestAutoCommit;
    
    my $siteUrl = $session->url->getSiteURL;
    my $date = $session->datetime;
    my $as = $form->get('as') || 'json';

    my $document = {
        title           => $file->getTitle,
        url             => $siteUrl.$file->getUrl,
        thumbnailUrl    => $siteUrl.$file->getThumbnailUrl,
        dateCreated     => $date->epochToHuman($file->get('creationDate'), '%y-%m-%d %j:%n:%s'),
        lastUpdated     => $date->epochToHuman($file->get('revisionDate'), '%y-%m-%d %j:%n:%s'),
    };
    if ($as eq "xml") {
        $session->http->setMimeType('text/xml');
        return XML::Simple::XMLout($document, NoAttr => 1);
    }
        
    $session->http->setMimeType('application/json');
    return JSON->new->pretty->encode($document);
}

#-----------------------------------------------------------------------------

=head2 www_delete ( )

Show the form to confirm deleting this album and all files inside of it.

=cut

sub www_delete {
    my $self        = shift;

    return $self->session->privilege->insufficient unless $self->canEdit;

    my $var         = $self->getTemplateVars;
    $var->{ url_yes     } = $self->getUrl("func=deleteConfirm");

    return $self->processStyle(
        $self->processTemplate( $var, $self->getParent->get("templateIdDeleteAlbum") )
    );
}

#-----------------------------------------------------------------------------

=head2 www_deleteConfirm ( )

Confirm deleting this album and all files inside of it.

=cut

sub www_deleteConfirm {
    my $self        = shift;

    return $self->session->privilege->insufficient unless $self->canEdit;

    my $gallery     = $self->getParent;
    my $i18n        = WebGUI::International->new( $self->session, 'Asset_GalleryAlbum' );

    $self->purge;
    
    return $self->processStyle(
        sprintf $i18n->get('delete message'), $self->getParent->getUrl,
    );
}

#----------------------------------------------------------------------------

=head2 www_ajax ( )

Generic AJAX service for gallery. 

Arguments are accepted in JSON format in the form variable C<args>. The single
obligatory argument is C<action> determining the service to be called. A list
of available services is given in the following. Additional arguments may be
required depending on the service.

Results are returned in JSON format. The information returned depends on the 
service called. Generally, success is indicated by a value of 0 in C<err>.

=head3 moveFile

Service for changing the rank of files. Accepts the asset Id of the photo to be moved
in C<target>. The asset Id of the photo to be replaced is specified in C<before>
or C<after> depending on the desired order. Returns -1 in C<err> and an error
message in C<errMessage> if moving of the photo failed.

=cut

sub www_ajax {
    my $self        = shift;
    my $session     = $self->session;
    my $form        = $self->session->form;
    my $result;

    # Get arguments encoded in json format
    my $args = decode_json($form->get("args"));
    
    # Log some debug information
    $session->log->debug("Ajax service called with args=" . $form->get("args"));
    
    # Process requests depending on action argument
    SWITCH: {

        # Return if no action was specified
        if ( $args->{action} eq '' ) {
            $session->log->error("Call of ajax service without action argument.");            
            $result->{ errMessage } = "Action argument is missing.";
            last;
        }
                
        # ----- Move file action -----
        $args->{action} eq 'moveFile' && do { $result = $self->_moveFileAjaxRequest( $args ); last; };
                    
        # ----- Unkown action -----
        $session->log->error("Call of ajax service with unknown action '" . $args->{action} . "'.");
        $result->{ errMessage } = "Action '" . $args->{action} ."' is unknown.";
    }
    
    # Set error flag if error message exists
    $result->{ err } = -1 if $result->{ errMessage };
    
    # Return results encoded in json format
    return encode_json( $result );
}


#----------------------------------------------------------------------------

=head2 _moveFileAjaxRequest ( args )

AJAX service for changing the rank of single files. Returns a hash ref with
error information. Arguments passed to the ajax service are provided via the 
hash ref C<args>. Note that this is a private function owned by www_ajax. It 
should not be used directly.

=cut

sub _moveFileAjaxRequest {
    my $self        = shift;
    my $args        = shift;
    
    my $session     = $self->session; 
    my %result;
            
    # Return if current user is not allowed to edit this album
    unless ( $self->canEdit ) {
        $session->log->error("Call of moveFile action without having edit permission.");
        $result{ errMessage } = "You do not have permission to move files.";
        return \%result;
    }            
    # Return if no target was specified
    if ( $args->{target} eq '') {
        $session->log->error("Call of moveFile action without target argument.");
        $result{ errMessage } = "Target argument is missing.";
        return \%result;
    }
    # Return if before or after argument is missing
    unless( $args->{before} or $args->{after} ) {
        $session->log->error("Call of moveFile action without before/after argument.");
        $result{ errMessage } = "Before/after argument is missing.";
        return \%result;
    }            
    # Return if before and after arguments were specified
    unless( $args->{before} xor $args->{after} ) {
        $session->log->error("Call of moveFile action with before *and* after argument.");
        $result{ errMessage } = "Both, before and after arguments were specified.";
        return \%result;
    }

    # Get Id of target photo and instantiate asset
    my $targetId = $args->{target};
    my $target = WebGUI::Asset->newByDynamicClass( $session, $targetId );

    # Return if target photo could not be instantiated
    unless ( $target ) {
        $session->log->error("Couldn't move file '$targetId' because we couldn't instantiate it.");
        $result{ errMessage } = "ID of target file seems to be invalid.";
        return \%result;
    }
    # Return if target is not a child of the current album
    unless ( $target->getParent->getId eq $self->getId ) {
        $session->log->error("Couldn't move file '$targetId' because it is not a child of this album.");
        $result{ errMessage } = "ID of target file seems to be invalid.";
        return \%result;
    }               

    my ($destId, $dest);

    # Instantiate file with ID in before/after argument
    $destId = $args->{before} ? $args->{before} : $args->{after};            
    $dest = WebGUI::Asset->newByDynamicClass( $session, $destId );

    # Return if destination file could not be instantiated
    unless ( $dest ) {
        $session->log->error("Couldn't move file '$targetId' before/after file '$destId' because we couldn't instantiate the latter.");
        $result{ errMessage } = "ID in before/after argument seems to be invalid.";
        return \%result;
    }               
    # Return if destination file is not a child of the current album
    unless ( $dest->getParent->getId eq $self->getId ) {
        $session->log->error("Couldn't move file '$targetId' before/after file '$destId' because the latter is not a child of the same album.");
        $result{ errMessage } = "ID in before/after argument seems to be invalid.";
        return \%result;
    }               

    # Check for use of after argument when lowering the rank
    if ( $args->{after} && $target->getRank() > $dest->getRank() ) {
        # Get ID of next sibling
        $destId = $self->getNextFileId( $destId );
        # Instantiate next sibling
        $dest = WebGUI::Asset->newByDynamicClass( $session, $destId );
    }
    # Check for use of before argument when increasing the rank
    if ( $args->{before} && $target->getRank() < $dest->getRank() ) {
        # Get ID of previous sibling
        $destId = $self->getPreviousFileId( $destId );
        # Instantiate previous sibling
        $dest = WebGUI::Asset->newByDynamicClass( $session, $destId );
    }
    
    # Update rank of target photo
    $target->setRank( $dest->getRank );
    
    # Log some debug information
    $session->log->debug("Successfully moved file '$targetId' before/after file '$destId'.");
    
    # Return reporting success
    $result{ err } = 0;        
    return \%result;
}

#----------------------------------------------------------------------------

=head2 www_edit ( )

Show the form to add / edit a GalleryAlbum asset.

Due to the advanced requirements of this form, we will ALWAYS post back to 
this page. This page will decide whether or not to make C<www_editSave> 
handle things.

=cut

sub www_edit {
    my $self        = shift;
    my $session     = $self->session;
    my $form        = $self->session->form;
    my $var         = $self->getTemplateVars;
    my $i18n        = WebGUI::International->new($session, 'Asset_GalleryAlbum');

    return $session->privilege->insufficient unless $self->canEdit;

    # Handle the button that was pressed
    # Save button
    if ( $form->get("save") ) {
        $self->processFileSynopsis;
        return $self->www_editSave;
    }
    # Cancel button
    elsif ( $form->get("cancel") ) {
        return $self->www_view;
    }
    # Promote the file
    elsif ( grep { $_ =~ /^promote-(.{22})$/ } $form->param ) {
        my $assetId     = ( grep { $_ =~ /^promote-(.{22})$/ } $form->param )[0];
        $assetId        =~ s/^promote-//;
        my $asset       = WebGUI::Asset->newByDynamicClass( $session, $assetId );
        if ( $asset ) {
            $asset->promote;
        }
        else {
            $session->errorHandler->error("Couldn't promote asset '$assetId' because we couldn't instantiate it.");
        }
    }
    # Demote the file
    elsif ( grep { $_ =~ /^demote-(.{22})$/ } $form->param ) {
        my $assetId     = ( grep { $_ =~ /^demote-(.{22})$/ } $form->param )[0];
        $assetId        =~ s/^demote-//;
        my $asset       = WebGUI::Asset->newByDynamicClass( $session, $assetId );
        if ( $asset ) {
            $asset->demote;
        }
        else {
            $session->errorHandler->error("Couldn't demote asset '$assetId' because we couldn't instantiate it.");
        }
    }
    # Rotate to the left
    elsif ( grep { $_ =~ /^rotateLeft-(.{22})$/ } $form->param ) {
        my $assetId     = ( grep { $_ =~ /^rotateLeft-(.{22})$/ } $form->param )[0];
        $assetId        =~ s/^rotateLeft-//;              
        my $asset       = WebGUI::Asset->newByDynamicClass( $session, $assetId );
        
        if ( $asset ) {
            # Add revision and create a new version tag by doing so
            my $newRevision = $asset->addRevision;
            # Rotate photo (i.e. all attached image files) by 90° CCW
            $newRevision->rotate(-90);           
            # Auto-commit version tag 
            $newRevision->requestAutoCommit;
       }
        else {
            $session->log->error("Couldn't rotate asset '$assetId' because we couldn't instantiate it.");
        }        
    }
    # Rotate to the right
    elsif ( grep { $_ =~ /^rotateRight-(.{22})$/ } $form->param ) {
        my $assetId     = ( grep { $_ =~ /^rotateRight-(.{22})$/ } $form->param )[0];
        $assetId        =~ s/^rotateRight-//;                
        my $asset       = WebGUI::Asset->newByDynamicClass( $session, $assetId );

        if ( $asset ) {
            # Add revision and create a new version tag by doing so
            my $newRevision = $asset->addRevision;
            # Rotate photo (i.e. all attached image files) by 90° CW
            $newRevision->rotate(90);           
            # Auto-commit version tag 
            $newRevision->requestAutoCommit;
        }
        else {
            $session->log->error("Couldn't rotate asset '$assetId' because we couldn't instantiate it.");
        }        
    }
    # Delete the file
    elsif ( grep { $_ =~ /^delete-(.{22})$/ } $form->param ) {
        my $assetId     = ( grep { $_ =~ /^delete-(.{22})$/ } $form->param )[0];
        $assetId        =~ s/^delete-//;
        my $asset       = WebGUI::Asset->newByDynamicClass( $session, $assetId );
        if ( $asset ) {
            $asset->purge;
        }
        else {
            $session->errorHandler->error( "Couldn't delete asset '$assetId' because we couldn't instanciate it.");
        }
    }

    # Generate the form
    if ($form->get("func") eq "add") {
        # Add page is exempt from our button handling code since it calls the Gallery www_editSave
        $var->{ isNewAlbum  } = 1;
        $var->{ form_start  } 
            = WebGUI::Form::formHeader( $session, {
                action      => $self->getParent->getUrl('func=editSave;assetId=new;class='.__PACKAGE__),
                extras      => 'name="galleryAlbumAdd"',
            })
            . WebGUI::Form::hidden( $session, {
                name        => "ownerUserId",
                value       => $session->user->userId,
            });

        # Put in the buttons that may ignore button handling code
        $var->{ form_cancel }
            = WebGUI::Form::button( $session, {
                name        => "cancel",
                value       => $i18n->get("cancel"),
                extras      => 'onclick="history.go(-1)"',
            });
    }
    else {
        $var->{ form_start  } 
            = WebGUI::Form::formHeader( $session, {
                action      => $self->getUrl('func=edit'),
                extras      => 'name="galleryAlbumEdit"',
            })
            . WebGUI::Form::hidden( $session, {
                name        => "ownerUserId",
                value       => $self->get("ownerUserId"),
            });
        
        # Put in the buttons that may ignore button handling code
        $var->{ form_cancel }
            = WebGUI::Form::submit( $session, {
                name        => "cancel",
                value       => $i18n->get("cancel"),
                extras      => 'onclick="history.go(-1)"',
            });
    }
    $var->{ form_start } 
        .= WebGUI::Form::hidden( $session, {
            name        => "proceed",
            value       => "showConfirmation",
        })
        ;

    $var->{ form_end    }
        = WebGUI::Form::formFooter( $session );

    $var->{ form_submit }
        = WebGUI::Form::submit( $session, {
            name        => "save",
            value       => $i18n->get("save"),
        });
    
    $var->{ form_title  }
        = WebGUI::Form::text( $session, {
            name        => "title",
            value       => $form->get("title") || $self->get("title"),
        });

    $var->{ form_description }
        = WebGUI::Form::HTMLArea( $session, {
            name        => "description",
            value       => $form->get("description") || $self->get("description"),
            richEditId  => $self->getParent->get("richEditIdAlbum"),
        });

    $var->{ form_othersCanAdd }
        = WebGUI::Form::yesNo( $session, {
            name        => "othersCanAdd",
            value       => $form->get( "othersCanAdd" ) || $self->get( "othersCanAdd" ),
        } );

    # Generate the file loop
    my $assetIdThumbnail    = $form->get("assetIdThumbnail") || $self->get("assetIdThumbnail");
    $self->appendTemplateVarsFileLoop( $var, $self->getFileIds );
    for my $file ( @{ $var->{file_loop} } ) {
        $file->{ form_assetIdThumbnail }
            = WebGUI::Form::radio( $session, {
                name        => "assetIdThumbnail",
                value       => $file->{ assetId },
                checked     => ( $assetIdThumbnail eq $file->{ assetId } ),
                id          => "assetIdThumbnail_$file->{ assetId }",
            } );

        my $promoteLabel    = $i18n->get( 'Move Up', 'Icon' );
        $file->{ form_promote }
            = WebGUI::Form::submit( $session, {
                name        => "promote-$file->{assetId}",
                value       => $i18n->get( 'Move Up', 'Icon' ),
                class       => "promote",
            });

        my $demoteLabel     = $i18n->get( 'Move Down', 'Icon' );
        $file->{ form_demote }
            = WebGUI::Form::submit( $session, {
                name        => "demote-$file->{assetId}",
                value       => $i18n->get( 'Move Down', 'Icon' ),
                class       => "demote",
            });

        my $deleteConfirm   = $i18n->get( 'template delete message', 'Asset_Photo' );
        $file->{ form_delete }
            = WebGUI::Form::submit( $session, {
                name        => "delete-$file->{assetId}",
                value       => $i18n->get( 'Delete', 'Icon' ),
                class       => "delete",
                extras      => "onclick=\"return confirm('$deleteConfirm')\"",
            });
            
        $file->{ form_rotateLeft }
            = WebGUI::Form::submit( $session, {
                name        => "rotateLeft-$file->{assetId}",
                value       => $i18n->get( 'rotate left' ),
                class       => "rotateLeft",
            });
               
        $file->{ form_rotateRight } 
            = WebGUI::Form::submit( $session, {
                name        => "rotateRight-$file->{assetId}",
                value       => $i18n->get( 'rotate right' ),
                class       => "rotateRight",
            });

        $file->{ form_synopsis }
            = WebGUI::Form::HTMLArea( $session, {
                name        => "fileSynopsis_$file->{assetId}",
                value       => $form->get( "fileSynopsis_$file->{assetId}" ) || $file->{ synopsis },
                richEditId  => $self->getParent->get( 'richEditIdFile' ),
                height      => 150,
                width       => 300,
            });
    }

    return $self->processStyle( 
        $self->processTemplate( $var, $self->getParent->get("templateIdEditAlbum") )
    );
}

#----------------------------------------------------------------------------

=head2 www_showConfirmation ( ) 

Shows the confirmation message after adding / editing a gallery album. 
Provides links to view the album.

=cut

sub www_showConfirmation {
    my $self        = shift;
    my $i18n        = WebGUI::International->new( $self->session, 'Asset_GalleryAlbum' );

    my $output      = '<p>' . sprintf( $i18n->get('save message'), $self->getUrl ) . '</p>'
                    . '<p>' . $i18n->get('what next') . '</p>'
                    . '<ul>'
                    . sprintf( '<li><a href="%s">%s</a></li>', $self->getUrl('func=add;class=WebGUI::Asset::File::GalleryFile::Photo'), $i18n->get('add photo')  )
                    . sprintf( '<li><a href="%s">%s</a></li>', $self->getUrl, $i18n->get('return to album') )
                    . '</ul>'
                    ;

    return $self->processStyle(
        $output
    );
}

#-----------------------------------------------------------------------------

=head2 www_slideshow ( )

Show a slideshow-type view of this album. The slideshow itself is powered by 
a javascript application in the template.

=cut

sub www_slideshow {
    my $self        = shift;

	my $check = $self->checkView;
	return $check if (defined $check);

    $self->{_templateVars} = $self->getTemplateVars;
    $self->appendTemplateVarsFileLoop( $self->{_templateVars}, $self->getFileIds );

    my $templateId = $self->getParent->get('templateIdViewSlideshow');
    my $template   = WebGUI::Asset::Template->new($self->session, $templateId);
    $template->prepare($self->getMetaDataAsTemplateVariables);
    $self->{_preparedTemplate} = $template;

    return $self->sendChunkedContent( sub { $self->view_slideshow } );
}

#----------------------------------------------------------------------------

=head2 www_thumbnails ( )

Show the thumbnails for the album.

=cut

sub www_thumbnails {
	my $self = shift;
	my $check = $self->checkView;
	return $check if (defined $check);
    $self->{_templateVars} = $self->getTemplateVars;
    $self->appendTemplateVarsFileLoop($self->{_templateVars}, $self->getFileIds);

    my $templateId = $self->getParent->get('templateIdViewThumbnails');
    my $template   = WebGUI::Asset::Template->new($self->session, $templateId);
    $template->prepare($self->getMetaDataAsTemplateVariables);
    $self->{_preparedTemplate} = $template;

    return $self->sendChunkedContent( sub { $self->view_thumbnails } );
}

#----------------------------------------------------------------------------

=head2 www_viewRss ( )

Display an RSS feed for this album.

=cut

sub www_viewRss {
    my $self        = shift;

    return $self->session->privilege->insufficient unless $self->canView;

    my $var         = $self->getTemplateVars;
    $self->appendTemplateVarsFileLoop( $var, $self->getFileIds );

    # Fix URLs to be full URLs
    for my $key ( qw( url url_viewRss ) ) {
        $var->{ $key } = $self->session->url->getSiteURL . $var->{ $key };
    }

    # Encode XML entities
    for my $key ( qw( title description synopsis gallery_title gallery_menuTitle ) ) {
        $var->{ $key } = WebGUI::HTML::filter($var->{$key}, 'xml');
    }

    # Process the file loop to add additional params
    for my $file ( @{ $var->{file_loop} } ) {
        # Fix URLs to be full URLs
        for my $key ( qw( url ) ) { 
            $file->{ $key }  = $self->session->url->getSiteURL . $file->{$key}; 
        }
        # Encode XML entities
        for my $key ( qw( title description synopsis ) ) {
            $file->{ $key } = WebGUI::HTML::filter($file->{$key}, 'xml');
        }

        $file->{ rssDate } 
            = $self->session->datetime->epochToMail( $file->{creationDate} );
    }

    $self->session->http->setMimeType('text/xml');
    return $self->processTemplate( $var, $self->getParent->get('templateIdViewAlbumRss') );
}

1;
