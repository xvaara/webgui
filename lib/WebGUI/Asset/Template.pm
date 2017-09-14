package WebGUI::Asset::Template;

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
use base 'WebGUI::Asset';
use WebGUI::International;
use WebGUI::Asset::Template::HTMLTemplate;
use WebGUI::Utility;
use WebGUI::Form;
use WebGUI::Exception;
use List::MoreUtils qw{ any };
use Tie::IxHash;
use Storable qw/dclone/;
use HTML::Packer;
use JSON qw{ to_json from_json };
use Try::Tiny;

=head1 NAME

Package WebGUI::Asset::Template

=head1 DESCRIPTION

Provides a mechanism to provide a templating system in WebGUI.

=head1 SYNOPSIS

use WebGUI::Asset::Template;


=head1 METHODS

These methods are available from this class:

=cut

#-------------------------------------------------------------------

=head2 addAttachments ( new_attachments )

Adds attachments to this template.  New attachments are added to the end of the current set of
attachments.

=head3 new_attachments

An arrayref of hashrefs, where each hashref should have at least url and type.  All
other keys will be ignored.

=cut

sub addAttachments {
    my ($self, $new_attachments) = @_;
    my $attachments = $self->getAttachments();

    foreach my $a (@{ $new_attachments }) {
        push @{ $attachments }, {
            url  => $a->{url},
            type => $a->{type},
        };
    }
    my $json = JSON->new->encode( $attachments );
    $self->update({ attachmentsJson => $json, });
}

#-------------------------------------------------------------------

=head2 cut ( )

Extend the base method to handle cutting the User Function Style template and destroying your site.
If the current template is the User Function Style template with the Fail Safe template.

=cut

sub cut {
    my ( $self )    = @_;
    my $returnValue = $self->SUPER::cut();
    if ($returnValue && $self->getId eq $self->session->setting->get('userFunctionStyleId')) {
        $self->session->setting->set('userFunctionStyleId', 'PBtmpl0000000000000060');
    }
    return $returnValue;
}

#-------------------------------------------------------------------

=head2 definition ( session, definition )

Defines the properties of this asset.

=head3 session

A reference to an existing session.

=head3 definition

A hash reference passed in from a subclass definition.

=cut

sub definition {
    my $class       = shift;
	my $session     = shift;
    my $definition  = shift;
	my $i18n        = WebGUI::International->new($session,"Asset_Template");
    push @{$definition}, {
		assetName   => $i18n->get('assetName'),
		icon        => 'template.gif',
        tableName   => 'template',
        className   => 'WebGUI::Asset::Template',
        properties  => {
            template => {
                fieldType       => 'codearea',
                syntax          => "html",
                defaultValue    => undef,
                filter          => 'packTemplate',
            },
            isEditable => {
                noFormPost      => 1,
                fieldType       => 'hidden',
                defaultValue    => 1,
            },
            isDefault => {
                fieldType       => 'hidden',
                defaultValue    => 0,
            },
            showInForms => {
                fieldType       => 'yesNo',
                defaultValue    => 1,
            },
            parser => {
                fieldType    => 'templateParser',
                defaultValue => $session->config->get('defaultTemplateParser'),
            },	
            namespace => {
                fieldType       => 'combo',
                defaultValue    => undef,
            },
            templatePacked => {
                fieldType       => 'hidden',
                defaultValue    => undef,
                noFormPost      => 1,
            },
            usePacked => {
                fieldType       => 'yesNo',
                defaultValue    => 0,
            },
            storageIdExample => {
                fieldType       => 'image',
            },
            attachmentsJson => {
                fieldType       => 'JsonTable',
            },
        },
    };
    return $class->SUPER::definition($session,$definition);
}

#-------------------------------------------------------------------

=head2 addRevision ( )

Override the master addRevision to copy attachments

=cut

sub addRevision {
    my ( $self, $properties, @args ) = @_;
    my $asset = $self->SUPER::addRevision($properties, @args);
    delete $properties->{templatePacked};
    return $asset;
}

#-------------------------------------------------------------------

=head2 drawExtraHeadTags ( )

Override the master drawExtraHeadTags to prevent Style template from having
Extra Head Tags.

=cut

sub drawExtraHeadTags {
	my ($self, $params) = @_;
    if ($self->get('namespace') eq 'style') {
        my $i18n = WebGUI::International->new($self->session);
        return $i18n->get(881);
    }
    return $self->SUPER::drawExtraHeadTags($params);
}


#-------------------------------------------------------------------

=head2 duplicate

Subclass the duplicate method so that the isDefault flag is set to 0 on any
copy.

=cut

sub duplicate {
	my $self = shift;
	my $newTemplate = $self->SUPER::duplicate(@_);
    $newTemplate->update({isDefault => 0});
    if ( my $storageId = $self->get('storageIdExample') ) {
        my $newStorage  = WebGUI::Storage->get( $self->session, $storageId )->copy;
        $newTemplate->update({ storageIdExample => $newStorage->getId });
    }
    return $newTemplate;
}

#-------------------------------------------------------------------

=head2 exportAssetData (  )

Override to add attachments to package data

=cut

sub exportAssetData {
    my ( $self ) = @_;
    my $data    = $self->SUPER::exportAssetData;
    if ( $self->get('storageIdExample') ) {
        push @{$data->{storage}}, $self->get('storageIdExample');
    }
    return $data;
}

#-------------------------------------------------------------------

=head2 getAttachments ( [type] )

Returns an arrayref of hashrefs representing all attachments for this template
of the specified type (link, bodyScript, headScript).

=head3 type

If defined, will limit the attachments to this type; e.g., passing
'stylesheet' will return only stylesheets.

=cut

sub getAttachments {
	my ( $self, $type ) = @_;

    return [] if !$self->get('attachmentsJson');

    my $attachments = JSON->new->decode( $self->get('attachmentsJson') );

    # We want it all and we want it now
    if ( !$type ) {
        return $attachments;
    }

    my $output  = [];
    for my $attach ( @{$attachments} ) {
        if ( $attach->{type} eq $type ) {
            push @{$output}, $attach;
        }
    }

    return $output;
}

#-------------------------------------------------------------------

=head2 getEditForm ( )

Returns the TabForm object that will be used in generating the edit page for this asset.

=cut

sub getEditForm {
	my $self = shift;
	my $session = $self->session;

	my ( $db, $url, $style, $form, $config )
	    = $session->quick(qw( db url style form config ));

	my $tabform = $self->SUPER::getEditForm();
	my $i18n = WebGUI::International->new($session, 'Asset_Template');

	my ( $properties, $meta, $display ) =
	    map { $tabform->getTab($_) } qw( properties meta display );

	my $returnUrl = $form->get('returnUrl');
	$tabform->hidden({
		name=>"returnUrl",
		value=>$returnUrl,
		});
	if ($self->getValue("namespace") eq "") {
		my $namespaces = $db->buildHashRef("select distinct(namespace) from template order by namespace");
		$properties->combo(
			-name=>"namespace",
			-options=>$namespaces,
			-label=>$i18n->get('namespace'),
			-hoverHelp=>$i18n->get('namespace description'),
			-value=>[$form->get("namespace")]
			);
	} else {
		$meta->readOnly(
			-label=>$i18n->get('namespace'),
			-hoverHelp=>$i18n->get('namespace description'),
			-value=>$self->getValue("namespace")
			);
		$meta->hidden(
			-name=>"namespace",
			-value=>$self->getValue("namespace")
			);
	}
	$display->yesNo(
		-name=>"showInForms",
		-value=>$self->getValue("showInForms"),
		-label=>$i18n->get('show in forms'),
		-hoverHelp=>$i18n->get('show in forms description'),
		);
	$properties->codearea(
		-name=>"template",
		-label=>$i18n->get('assetName'),
		-hoverHelp=>$i18n->get('template description'),
		-syntax => "html",
		-value=>$self->getValue("template")
		);
	$properties->raw(qq(
	    <tr>
	        <td class='formDescription' valign='top'>
	            ${\ $i18n->get('Preview') }
	        </td>
	        <td class='tableData'>
	            <input type='button'
	                   value='${\ $i18n->get('Preview') }'
	                   id='preview'/>
	            <input type='button'
	                   value='${\ $i18n->get('Configure') }'
	                   id='previewConfig'/>
	        </td>
	    </tr>
	));
	my $cform = WebGUI::HTMLForm->new($session);
	$cform->yesNo(
	    id        => 'previewRaw',
	    name      => 'previewRaw',
	    label     => $i18n->get('Plain Text?'),
	    hoverHelp => $i18n->get('Plain Text hoverHelp'),
	);
	$cform->text(
	    id           => 'previewFetchUrl',
	    label        => $i18n->get('URL'),
	    hoverHelp    => $i18n->get('URL hoverHelp'),
	    defaultValue => $returnUrl,
	);
	$cform->button(
	    id        => 'previewFetch',
	    label     => $i18n->get('Fetch Variables'),
	    hoverHelp => $i18n->get('Fetch Variables hoverHelp'),
	    value     => $i18n->get('Fetch'),
	);
	$cform->codearea(
	    id        => 'previewVars',
	    label     => $i18n->get('Variables'),
	    hoverHelp => $i18n->get('Variables hoverHelp'),
	);

	$cform->hidden(id => 'previewId', value => $self->getId);
	$cform->hidden(id => 'previewGateway', value => $url->gateway);
	$properties->raw(qq(
	    <tr>
	    <td></td>
	    <td>
	        <div id='previewConfigForm'>
	            <div class='hd'>${\ $i18n->get('Configure Preview') }</div>
	            <table class='bd'>${\ $cform->printRowsOnly }</table>
	            <div class='ft' style='margin:0 auto; text-align: center'>
	                <button id='previewConfigClose'>Close</button>
	            </div>
	        </div>
	    </td>
	    </tr>
	));

	$properties->yesNo(
	    name        => "usePacked",
	    label       => $i18n->get('usePacked label'),
	    hoverHelp   => $i18n->get('usePacked description'),
	    value       => $self->getValue("usePacked"),
	);

	$style->setScript($url->extras($_)) for qw(
	    yui/build/json/json-min.js
	    yui/build/container/container-min.js
	    templatePreview.js
	);

	$properties->templateParser(
		name      => 'parser',
		label     => $i18n->get('parser'),
		hoverHelp => $i18n->get('parser description'),
		value     => $self->getValue('parser'),
	);

	$properties->jsonTable(
	    name        => 'attachmentsJson',
	    value       => $self->get('attachmentsJson'),
	    label       => $i18n->get("attachment display label"),
	    fields      => [
	        {
	            type            => "text",
	            name            => "url",
	            label           => $i18n->get('attachment header url'),
	            size            => '48',
	        },
	        {
	            type            => "select",
	            name            => "type",
	            label           => $i18n->get('attachment header type'),
	            options         => [
	                stylesheet => $i18n->get('css label'),
	                headScript => $i18n->get('js head label'),
	                bodyScript => $i18n->get('js body label'),
	            ],
	        },
	    ],
	);

	$properties->image(
	    name        => 'storageIdExample',
	    value       => $self->getValue('storageIdExample'),
	    label       => $i18n->get('field storageIdExample'),
	    hoverHelp   => $i18n->get('field storageIdExample description'),
	);

	return $tabform;
}

#-------------------------------------------------------------------

=head2 getExampleImageUrl ( )

Get the URL to the example image of this template, if any

=cut

sub getExampleImageUrl {
    my ( $self ) = @_;
    if ( my $storageId = $self->get('storageIdExample') ) {
        my $storage = WebGUI::Storage->get( $self->session, $storageId );
        return $storage->getUrl( $storage->getFiles->[0] );
    }
    return;
}

#-------------------------------------------------------------------

=head2 getList ( session, namespace [,clause] )

Returns a hash reference containing template ids and template names of all the templates in the specified namespace.

NOTE: This is a class method.

=head3 session

A reference to the current session.

=head3 namespace

Specify the namespace to build the list for.  If no namespace is specified,
then an empty hash reference will be returned.

=head3 clause

An extra clause that can be used to further limit the list, such as "assetData.status='approved'

=cut

sub getList {
	my $class = shift;
	my $session = shift;
	my $namespace = shift;
    my $clause      = shift;
    if ($clause) {
        $clause = ' and ' . $clause;
    }
    else {
        $clause = '';
    }
	my $sql = "select asset.assetId, assetData.revisionDate from template left join asset on asset.assetId=template.assetId left join assetData on assetData.revisionDate=template.revisionDate and assetData.assetId=template.assetId where template.namespace=? and template.showInForms=1 and asset.state='published' and assetData.revisionDate=(SELECT max(revisionDate) from assetData where assetData.assetId=asset.assetId and (assetData.status='approved' or assetData.tagId=?)) $clause order by assetData.title";
	my $sth = $session->dbSlave->read($sql, [$namespace, $session->scratch->get("versionTag")]);
	my %templates;
	tie %templates, 'Tie::IxHash';
	while (my ($id, $version) = $sth->array) {
		$templates{$id} = WebGUI::Asset::Template->new($session,$id,undef,$version)->getTitle;
	}	
	$sth->finish;	
	return \%templates;
}

#-------------------------------------------------------------------

=head2 getParser ( session, parser )

Returns a template parser object.

NOTE: This is a class method.

=head3 session

A reference to the current session.

=head3 parser

A parser class to use. Defaults to "WebGUI::Asset::Template::HTMLTemplate"

=cut

sub getParser {
    my $class = shift;
    my $session = shift;
    my $parser = shift;

    # If parser is not in the config, throw an error message
    if ( $parser && $parser ne $session->config->get('defaultTemplateParser') 
                && !any { $_ eq $parser } @{$session->config->get('templateParsers')} ) {
        WebGUI::Error::NotInConfig->throw(
            error       => "Attempted to load template parser '$parser' that is not in config file",
            module      => $parser,
            configKey   => 'templateParsers',
        );
    }
    else {
        $parser ||= $session->config->get("defaultTemplateParser") || "WebGUI::Asset::Template::HTMLTemplate";
    }

    WebGUI::Pluggable::load( $parser );
    return $parser->new($session);
}

#-------------------------------------------------------------------
#
# See the warning about using this on processVariableHeaders(). If no
# variables were captured, we'll return the empty string.

sub getVariableJson {
    my ($class, $session) = @_;
    my ($show, $vars, $json);

    return ($show = $session->stow->get('showTemplateVars'))
        && ($vars = $show->{vars})
        && ($json = eval { JSON::encode_json($vars) })
        && ($show->{startDelimiter} . $json . $show->{endDelimiter})
        or '';
}

#-------------------------------------------------------------------

=head2 importAssetCollateralData ( data )

Override to import attachments from old versions of WebGUI

=cut

sub importAssetCollateralData {
    my ( $self, $data, @args ) = @_;
    if ( $data->{template_attachments} ) {
        $self->update( { attachmentsJson => JSON::to_json($data->{template_attachments}) } );
    }
    return $self->SUPER::importAssetCollateralData( $data, @args );
}

    
#-------------------------------------------------------------------

=head2 indexContent ( )

Making private. See WebGUI::Asset::indexContent() for additonal details. 

=cut

sub indexContent {
	my $self = shift;
	my $indexer = $self->SUPER::indexContent;
	$indexer->addKeywords($self->get("namespace"));
	$indexer->setIsPublic(0);
}

#-------------------------------------------------------------------

=head2 packTemplate ( template )

Pack the template into a minified version for faster downloads.

=cut

sub packTemplate {
    my ( $self, $template ) = @_;
    my $packed  = $template;
    HTML::Packer::minify( \$packed, {
        do_javascript       => "shrink",
        do_stylesheet       => "minify",
    } );
    $self->update({ templatePacked => $packed });
    return $template;
}

#-------------------------------------------------------------------

=head2 prepare ( headerTemplateVariables )

This method sets the tags from the head block parameter of the template into the HTML head block in the style. You only need to call this method if you're using the HTML streaming features of WebGUI, like is done in the prepareView()/view()/www_view() methods of WebGUI assets.

=head3 headerTemplateVariables

A hash reference containing template variables to be processed for the head block. Typically obtained via $asset->getMetaDataAsTemplateVariables.

=cut

sub prepare {
	my $self = shift;
	my $vars = shift;
	$self->{_prepared} = 1;

	my $sent = $self->session->stow->get('templateHeadersSent');
	unless ($sent) {
		$self->session->stow->set('templateHeadersSent', $sent = []);
	}

	my $id   = $self->getId;
	# don't send head block if we've already sent it for this template
	return if isIn($id, @$sent);

	my $session      = $self->session;
	my ($db, $style) = $session->quick(qw(db style));
	my $parser       = $self->getParser($session, $self->get('parser'));
	my $headBlock    = $parser->process($self->getExtraHeadTags, $vars);

	$style->setRawHeadTags($headBlock);

    my %props = ( type => 'text/css', rel => 'stylesheet' );
	foreach my $sheet ( @{ $self->getAttachments('stylesheet') } ) {
		$style->setLink($sheet->{url}, \%props);
	}

	my $doScripts = sub {
		my ($type, $body) = @_;
        my %props = ( type => 'text/javascript' );
		foreach my $script ( @{ $self->getAttachments($type) } ) {
			$style->setScript($script->{url}, \%props, $body);
		}
	};

	$doScripts->('headScript');
	$doScripts->('bodyScript', 1);

	push(@$sent, $id);
}


#-------------------------------------------------------------------

=head2 process ( vars )

Evaluate a template replacing template commands for HTML.  If the internal property templatePacked
is set to true, the packed, minimized template will be used.  Otherwise, the original template
will be used.

=head3 vars

A hash reference containing template variables and loops. Automatically includes the entire WebGUI session.

=cut

sub process {
	my $self    = shift;
	my $vars    = shift;
    my $session = $self->session;

    if ($self->get('state') =~ /^trash/) {
        my $i18n = WebGUI::International->new($session, 'Asset_Template');
        my $url  = $session->asset ? $session->asset->get('url')  ##Called via asset
                                   : $session->url->getRaw();     ##Called via operation, like auth
        $session->errorHandler->warn('process called on template in trash: '.$self->getId
            .". The template was called through this url: $url");
        return $session->var->isAdminOn ? $i18n->get('template in trash') : '';
    }
    elsif ($self->get('state') =~ /^clipboard/) {
        my $i18n = WebGUI::International->new($session, 'Asset_Template');
        my $url  = $session->asset ? $session->asset->get('url')
                                   : $session->url->getRaw();
        $session->errorHandler->warn('process called on template in clipboard: '.$self->getId
            .". The template was called through this url: $url");
        return $session->var->isAdminOn ? $i18n->get('template in clipboard') : '';
    }

    # Return a JSONinfied version of vars if JSON is the only requested content type.
    if ( defined $session->request && $session->request->headers_in->{Accept} eq 'application/json' ) {
       $session->http->setMimeType( 'application/json' );
       return to_json( $vars );
    }

    my $stow = $session->stow;
    my $show = $stow->get('showTemplateVars');
    if ( $show && $show->{assetId} eq $self->getId && $self->canEdit ) {
        # This will never be true again, cause we're getting rid of assetId
        delete $show->{assetId};
        $show->{vars} = $vars;
        $stow->set( showTemplateVars => $show );
    }

	$self->prepare unless ($self->{_prepared});
    my $parser      = $self->getParser($session, $self->get("parser"));
    my $template    = $self->get('usePacked')
                    ? $self->get('templatePacked')
                    : $self->get('template')
                    ;
    my $output;
    eval { $output = $parser->process($template, $vars); };
    if (my $e = Exception::Class->caught) {
    	my $message = ref $e ? $e->error : $e;
        $session->log->error(sprintf "Error processing template: %s, %s, %s", $self->getUrl, $self->getId, $message);
        my $i18n = WebGUI::International->new($session, 'Asset_Template');
        $output = sprintf $i18n->get('template error').$message, $self->getUrl, $self->getId;
    }
	return $output;
}

#-------------------------------------------------------------------

# Used for debugging and the template test renderer.

# WARNING: Please do not rely on this behavior. It's a bit of a hack, and
# should not be considered part of the core API. Eventually, we will have
# introspectable template objects so that you can more easily (and
# efficiently) get this kind of information.

# If the first value for the 'X-Webgui-Template-Variables' header is our
# assetId, then in addition to processing the template, append add a json
# representation of our template variables to the response. The headers
# "X-Webgui-Template-Variables-Start" and "X-Webgui-Template-Variables-End"
# will contain the delimiters for the start and end of this content so that
# the user agent (who had to have stuck the header in in the first place) can
# parse it out.  The delimiters will make the whole thing look like an xml
# comment (<!-- ... -->) just in case.

# We would just send the vars in the header, but different webservers have
# different limits on header field size and it's impossible to say whether our
# data will fit inside them or not.

# This is intended to be called earlier in the request cycle (in the Content
# URL handler) so that the headers get sent before any chunked content starts
# being set up.  We set the stow here and check it during process() to see
# whether we need to include the delimited json. Later on, Content will call
# call getVariableJson to get the results.

{
    my $head = 'X-Webgui-Template-Variables';
    my @chr  = ('0'..'9', 'a'..'z', 'A'..'Z');

    sub processVariableHeaders {
        my ($class, $session) = @_;
        my $r = $session->request;
        if (my $id = $r->headers_in->{$head}) {
            my $rnd = join('', map { $chr[int(rand($#chr))] } (1..32));
            my $out = $r->headers_out;
            my $st  = "<!-- $rnd ";
            my $end = " $rnd -->";
            $out->{"$head-Start"} = $st;
            $out->{"$head-End"}   = $end;
            $session->stow->set(
                showTemplateVars => {
                    assetId        => $id,
                    startDelimiter => $st,
                    endDelimiter   => $end,
                }
            );
        }
    }
}

#-------------------------------------------------------------------

=head2 processPropertiesFromFormPost 

Extends the master class to handle template parsers, namespaces and template attachments.

=cut

sub processPropertiesFromFormPost {
	my $self = shift;
        my $session = $self->session;
	$self->SUPER::processPropertiesFromFormPost;
    # TODO: Perhaps add a way to check template syntax before it blows stuff up?
    my %data;
    my $needsUpdate = 0;
	if ($self->getValue("parser") ne $self->session->form->process("parser","className") && ($self->session->form->process("parser","className") ne "")) {
        $needsUpdate = 1;
		if (isIn($self->session->form->process("parser","className"),@{$self->session->config->get("templateParsers")})) {
			%data = ( parser => $self->session->form->process("parser","className") );
		} else {
			%data = ( parser => $self->session->config->get("defaultTemplateParser") );
		}
	}
	if ($self->session->form->process("namespace") eq 'style') {
        $needsUpdate = 1;
        $data{extraHeadTags} = '';
    }

    if ($needsUpdate) {
        $self->update(\%data);
    }

    ### Template attachments
    $self->update({ attachmentsJson => $session->form->process( 'attachmentsJson', 'JsonTable' ), });

    return;
}

#-------------------------------------------------------------------

=head2 processRaw ( session, template, vars [ , parser ] )

Process an arbitrary template string. This is a class method.

=head3 session

A reference to the current session.

=head3 template

A scalar containing the template text.

=head3 vars

A hash reference containing template variables.

=head3 parser

Optionally specify the class name of a parser to use.

=cut

sub processRaw {
	my $class = shift;
	my $session = shift;
	my $template = shift;
	my $vars = shift;
	my $parser = shift;
	return $class->getParser($session,$parser)->process($template, $vars);
}

#-------------------------------------------------------------------

=head2 purge ( )

Extend the base method to handle purging the User Function Style template and destroying your site.
If the current template is the User Function Style template with the Fail Safe template.

=cut

sub purge {
	my $self = shift;
    my $returnValue = $self->SUPER::purge;
    if ($returnValue && $self->getId eq $self->session->setting->get('userFunctionStyleId')) {
        $self->session->setting->set('userFunctionStyleId', 'PBtmpl0000000000000060');
    }
	return $returnValue;
}

#-------------------------------------------------------------------

=head2 removeAttachments ( urls )

Removes attachments. 

=head3 urls

C<urls> is an arrayref of URLs to remove. If C<urls>
is not defined, will remove all attachments for this revision.

=cut

sub removeAttachments {
    my ($self, $urls) = @_;

    my @attachments = ();

    if ($urls) {
        @attachments = grep { !isIn($_->{url}, @{ $urls }) } @{ $self->getAttachments() };
    }

    my $json = JSON->new->encode( \@attachments );
    $self->update({ attachmentsJson => $json, });
}

#-------------------------------------------------------------------

=head2 update

Override update from Asset.pm to handle backwards compatibility with the old
packages that contain headBlocks. This will be removed in the future.  Don't plan
on this being here.

=cut

sub update {
    my $self = shift;
    my $requestedProperties = shift || {};
    my $properties = dclone($requestedProperties);

    if (exists $properties->{headBlock}) {
        $properties->{extraHeadTags} .= $properties->{headBlock};
        delete $properties->{headBlock};
    }

    $self->SUPER::update($properties);
}


#-------------------------------------------------------------------

=head2 www_edit 

Hand draw this form so that a warning can be displayed to the user when editing a
default template.

=cut

sub www_edit {
    my $self = shift;
    return $self->session->privilege->insufficient() unless $self->canEdit;
    return $self->session->privilege->locked() unless $self->canEditIfLocked;
    my $session = $self->session;
    my $form    = $session->form;
    my $url     = $session->url;
    my $i18n    = WebGUI::International->new($session, "Asset_Template");
    my $output  = '';

    # Add an unfriendly warning message if this is a default template
    if ( $self->get( 'isDefault' ) ) {
        # Get a proper URL to make the duplicate
        my $duplicateUrl = $self->getUrl( "func=editDuplicate" );
        if ( $form->get( "proceed" ) ) {
            $duplicateUrl = $url->append( $duplicateUrl, "proceed=" . $form->get( "proceed" ) );
            if ( $form->get( "returnUrl" ) ) {
                $duplicateUrl = $url->append( $duplicateUrl, "returnUrl=" . $form->get( "returnUrl" ) );
            }
        }
        
        $session->style->setRawHeadTags( <<'ENDHTML' );
<style type="text/css">
.wGwarning { 
    border              : 1px solid red;
    background-color    : #FF6666;
    padding             : 10px;
    margin              : 5px;
    /* TODO: Add a nice little image here */
    /* TODO: Make this a generic warning class from the default webgui stylesheet */
}
</style>
ENDHTML

        $output .= q{<div class="wGwarning"><p>}
                . $i18n->get( "warning default template" )
                . q{</p><p>}
                . sprintf( q{<a href="} . $duplicateUrl . q{">%s</a>}, $i18n->get( "make duplicate label" ) )
                . q{</p></div>}
                ;
    }
    
    $output .= $self->getEditForm->print;

    $self->getAdminConsole->addSubmenuItem($self->getUrl('func=styleWizard'),$i18n->get("style wizard")) if ($self->get("namespace") eq "style");
    return $self->getAdminConsole->render( $output, $i18n->get('edit template') );
}

#-------------------------------------------------------------------

=head2 www_goBackToPage 

If set, redirect the user to the URL set by the form variable C<returnUrl>.  Otherwise, it returns
the user back to the site.

=cut

sub www_goBackToPage {
	my $self = shift;
	$self->session->http->setRedirect($self->session->form->get("returnUrl")) if ($self->session->form->get("returnUrl"));
	return undef;
}

#----------------------------------------------------------------------------

=head2 www_editDuplicate

Make a duplicate of this template and edit that instead.

=cut

sub www_editDuplicate {
    my $self        = shift;
    return $self->session->privilege->insufficient() unless $self->canEdit;

    my $session     = $self->session;
    my $form        = $self->session->form;

    my $newTemplate = $self->duplicate;
    $newTemplate->update( { 
        isDefault   => 0, 
        title       => $self->get( "title" ) . " (copy)",
        menuTitle   => $self->get( "menuTitle" ) . " (copy)",
    } );

    # Make the asset that originally invoked edit template use the newly created asset.
    if ( $self->session->form->get( "proceed" ) eq "goBackToPage" ) {
        if ( my $asset = WebGUI::Asset->newByUrl( $session, $form->get( "returnUrl" ) ) ) {
            # Find which property we should set by comparing namespaces and current values
            DEF: for my $def ( @{ $asset->definition( $self->session ) } ) {
                my $properties  = $def->{ properties };
                PROP: for my $prop ( keys %{ $properties } ) {
                    next PROP unless lc $properties->{ $prop }->{ fieldType } eq "template";
                    next PROP unless $asset->get( $prop ) eq $self->getId;
                    if ( $properties->{ $prop }->{ namespace } eq $self->get( "namespace" ) ) {
                        $asset->addRevision( { $prop => $newTemplate->getId } );

                        # Auto-commit our revision if necessary
                        # TODO: This needs to be handled automatically somehow...
                        my $status = WebGUI::VersionTag->autoCommitWorkingIfEnabled($self->session);
                        ##get a fresh object from the database
                        if ($status eq 'commit') {
                            $newTemplate = $newTemplate->cloneFromDb;
                        }
                        last DEF;
                    }
                }
            }
        }
    }
    
    return $newTemplate->www_edit;
}

#-------------------------------------------------------------------

=head2 www_manage 

If trying to use the assetManager on this asset, push them back to managing the
template's parent instead.

=cut

sub www_manage {
	my $self = shift;
	#takes the user to the folder containing this template.
	return $self->getParent->www_manageAssets;
}


#-------------------------------------------------------------------

=head2 www_styleWizard 

Edit form for building style templates in a WYSIWIG fashion.

=cut

sub www_styleWizard {
	my $self = shift;
    return $self->session->privilege->insufficient() unless $self->canEdit;
    return $self->session->privilege->locked() unless $self->canEditIfLocked;
	my $i18n = WebGUI::International->new($self->session, "Asset_Template");
	my $form = $self->session->form;
	my $output = "";
	if ($form->get("step") == 2) {
		my $f = WebGUI::HTMLForm->new($self->session,{action=>$self->getUrl});
		$f->hidden(name=>"func", value=>"styleWizard");
		$f->hidden(name=>"proceed", value=>"manageAssets") if ($form->get("proceed"));
		$f->hidden(name=>"step", value=>3);
		$f->hidden(name=>"layout", value=>$form->get("layout"));
		$f->text(
			name=>"heading",
			value=>"My Site",
			label=>$i18n->get("site name"),
			hoverHelp=>$i18n->get("site name description")
		);
		$f->file(
			name=>"logo",
			label=>$i18n->get("logo"),
			hoverHelp=>$i18n->get("logo description"),
			subtext=>$i18n->get("logo subtext")
		);
		$f->color(
			name=>"pageBackgroundColor",
			value=>"#ccccdd",
			label=>$i18n->get("page background color"),
			hoverHelp=>$i18n->get("page background color description"),
		);
		$f->color(
			name=>"headingBackgroundColor",
			value=>"#ffffff",
			label=>$i18n->get("header background color"),
			hoverHelp=>$i18n->get("header background color description"),
		);
		$f->color(
			name=>"headingForegroundColor",
			value=>"#000000",
			label=>$i18n->get("header text color"),
			hoverHelp=>$i18n->get("header text color description"),
		);
		$f->color(
			name=>"bodyBackgroundColor",
			value=>"#ffffff",
			label=>$i18n->get("body background color"),
			hoverHelp=>$i18n->get("body background color description"),
		);
		$f->color(
			name=>"bodyForegroundColor",
			value=>"#000000",
			label=>$i18n->get("body text color"),
			hoverHelp=>$i18n->get("body text color description"),
		);
		$f->color(
			name=>"menuBackgroundColor",
			value=>"#eeeeee",
			label=>$i18n->get("menu background color"),
			hoverHelp=>$i18n->get("menu background color description"),
		);
		$f->color(
			name=>"linkColor",
			value=>"#0000ff",
			label=>$i18n->get("link color"),
			hoverHelp=>$i18n->get("link color description"),
		);
		$f->color(
			name=>"visitedLinkColor",
			value=>"#ff00ff",
			label=>$i18n->get("visited link color"),
			hoverHelp=>$i18n->get("visited link color description"),
		);
		$f->submit;
		$output = $f->print;
	} elsif ($form->get("step") == 3) {
		my $storageId = $form->get("logo","file");
		my $logo;
		my $logoContent = '';
		if ($storageId) {
			my $storage = WebGUI::Storage->get($self->session,$storageId);
			$logo = $self->addChild({
				className=>"WebGUI::Asset::File::Image",
				title=>join(' ', $form->get("heading"), $i18n->get('logo')),
				menuTitle=>join(' ', $form->get("heading"), $i18n->get('logo')),
				url=>join(' ', $form->get("heading"), $i18n->get('logo')),
				storageId=>$storage->getId,
				filename=>@{$storage->getFiles}[0],
				templateId=>"PBtmpl0000000000000088"
				});
			$logo->generateThumbnail;
			$logoContent = '<div class="logo"><a href="^H(linkonly);">^AssetProxy('.$logo->get("url").');</a></div>';
		}
		my $customHead = '';
		if ($form->get("layout") eq "1") {
			$customHead .= '
			.bodyContent {
			 	background-color: '.$form->get("bodyBackgroundColor","color").';
                		color: '.$form->get("bodyForegroundColor","color").';
				width: 70%; 
				float: left;
			}
			.menu {
				width: 30%;
				float: left;
			}
			.wrapper { 
				width: 80%;
				margin-right: 10%;
				margin-left: 10%;
				background-color: '.$form->get("menuBackgroundColor","color").';
			}
			';
		} else {
			$customHead .= '
			.bodyContent {
			 	background-color: '.$form->get("bodyBackgroundColor","color").';
                		color: '.$form->get("bodyForegroundColor","color").';
				width: 100%;
			}
			.menu {
                		background-color: '.$form->get("menuBackgroundColor","color").';
				width: 100%;
				text-align: center;
			}
			.wrapper { 
				width: 80%;
				margin-right: 10%;
				margin-left: 10%;
			}
			';
		}
		my $style = '<html>
<head>
	<tmpl_var head.tags>
	<title>^Page(title); - ^c;</title>
	<style type="text/css">
	.siteFunctions {
		float: right;
		font-size: 12px;
	}
	.copyright {
		font-size: 12px;
	}
	body {
		background-color: '.$form->get("pageBackgroundColor","color").';
		font-family: helvetica;
		font-size: 14px;
	}
	.heading {
		background-color: '.$form->get("headingBackgroundColor","color").';
		color: '.$form->get("headingForegroundColor","color").';
		font-size: 30px;
		margin-left: 10%;
		margin-right: 10%;
		vertical-align: middle;
	}
	.logo {
		width: 200px; 
		float: left;
		text-align: center;
	}
	.logo img {
		border: 0px;
	}
	.endFloat {
		clear: both;
	}
	.padding {
		padding: 5px;
	}
	'.$customHead.'
	a {
		color: '.$form->get("linkColor","color").';
	}
	a:visited {
		color: '.$form->get("visitedLinkColor","color").';
	}
	</style>
</head>
<body>
^AdminBar;
<div class="heading">
	<div class="padding">
		'.$logoContent.'
		'.$form->get("heading").'
		<div class="endFloat"></div>
	</div>
</div>
<div class="wrapper">
	<div class="menu">
		<div class="padding">^AssetProxy('.($form->get("layout") == 1 ? 'flexmenu' : 'toplevelmenuhorizontal').');</div>
	</div>
	<div class="bodyContent">
		<div class="padding"><tmpl_var body.content></div>
	</div>
	<div class="endFloat"></div>
</div>
<div class="heading">
	<div class="padding">
		<div class="siteFunctions">^a(^@;); ^AdminToggle;</div>
		<div class="copyright">&copy; ^D(%y); ^c;</div>
	<div class="endFloat"></div>
	</div>
</div>
</body>
</html>';
		return $self->addRevision({
			template=>$style
			})->www_edit;
	} else {
		$output = WebGUI::Form::formHeader($self->session,{action=>$self->getUrl}).WebGUI::Form::hidden($self->session,{name=>"func", value=>"styleWizard"});
		$output .= WebGUI::Form::hidden($self->session,{name=>"proceed", value=>"manageAssets"}) if ($form->get("proceed"));
		$output .= '<style type="text/css">
			.chooser { float: left; width: 150px; height: 150px; } 
			.representation, .representation td { font-size: 12px; width: 120px; border: 1px solid black; } 
			.representation { height: 130px; }
			</style>';
		$output .= $i18n->get('choose a layout');
		$output .= WebGUI::Form::hidden($self->session,{name=>"step", value=>2});
		$output .= '<div class="chooser">'.WebGUI::Form::radio($self->session,{name=>"layout", value=>1, checked=>1}).sprintf(q|<table class="representation"><tbody>
			<tr><td>%s</td><td>%s</td></tr>
			<tr><td>%s</td><td>%s</td></tr>
			</tbody></table></div>|,
			$i18n->get('logo'),
			$i18n->get('heading'),
			$i18n->get('menu'),
			$i18n->get('body content'),
			);
		$output .= '<div class="chooser">'.WebGUI::Form::radio($self->session,{name=>"layout", value=>2}).sprintf(q|<table class="representation"><tbody>
			<tr><td>%s</td><td>%s</td></tr>
			<tr><td style="text-align: center;" colspan="2">%s</td></tr>
			<tr><td colspan="2">%s</td></tr>
			</tbody></table></div>|,
			$i18n->get('logo'),
			$i18n->get('heading'),
			$i18n->get('menu'),
			$i18n->get('body content'),
			);
		$output .= WebGUI::Form::submit($self->session);
		$output .= WebGUI::Form::formFooter($self->session);
	}
	$self->getAdminConsole->addSubmenuItem($self->getUrl('func=edit'),$i18n->get("edit template")) if ($self->get("url"));
        return $self->getAdminConsole->render($output,$i18n->get('style wizard'));
}

#-------------------------------------------------------------------

=head2 www_preview

Rendes this template with the given variables (posted as JSON)

=cut

sub www_preview {
    my $self    = shift;
    my $session = $self->session;
    return $session->privilege->insufficient unless $self->canEdit;

    my $form = $session->form;
    my $http = $session->http;

    try {
        my $output = $self->processRaw(
            $session,
            $form->get('template'),
            from_json($form->get('variables')),
            $form->get('parser'),
        );
        if ($form->get('plainText')) {
            $http->setMimeType('text/plain');
        }
        elsif ($output !~ /<html>/) {
            $output = $session->style->userStyle($output);
        }
        return $output;
    } catch {
        $http->setMimeType('text/plain');
        $_[0];
    }
}

#-------------------------------------------------------------------

=head2 www_view 

Override the default behavior.  When a template is viewed, it redirects you
to viewing the template's container instead.

=cut

sub www_view {
	my $self = shift;
	return $self->session->asset($self->getContainer)->www_view;
}



1;
