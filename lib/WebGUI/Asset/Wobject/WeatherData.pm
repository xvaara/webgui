package WebGUI::Asset::Wobject::WeatherData;

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
use Weather::Com::Finder;
use WebGUI::International;
use Class::C3;
use base qw/WebGUI::Asset::Wobject WebGUI::AssetAspect::Dashlet/;
use WebGUI::Utility;

#-------------------------------------------------------------------

=head2 definition ( )

defines wobject properties for WeatherData instances

=cut

sub definition {
	my $class = shift;
	my $session = shift;
	my $definition = shift;
	my $i18n = WebGUI::International->new($session, "Asset_WeatherData");
	my $properties = {
		partnerId => {
			fieldType 	=> "text",
			tab 		=> "properties",
			defaultValue	=> undef,
			hoverHelp	=> $i18n->get("partnerId help"),
			label		=> $i18n->get("partnerId"),
			subtext		=> '<a href="http://www.weather.com/services/xmloap.html">'.$i18n->get("you need a weather.com key").'</a>',
			},
		licenseKey => {
			fieldType	=> "text",
			tab		=> "properties",
			defaultValue	=> undef,
			hoverHelp	=> $i18n->get("licenseKey help"),
			label		=> $i18n->get("licenseKey"),
			},
		templateId =>{
			fieldType=>"template",
			tab=>"display",
			defaultValue=>'WeatherDataTmpl0000001',
			namespace=>"WeatherData",
			hoverHelp=>$i18n->get("Current Weather Conditions Template to use"),
			label=>$i18n->get("Template")
		},
		locations=>{
			fieldType=>"textarea",
			defaultValue=>"Madison, WI\nToronto, Canada\n53536",
			tab=>"properties",
			hoverHelp=>$i18n->get("Your list of default weather locations"),
			label=>$i18n->get("Default Locations"),
            dashletOverridable => 1,
		},
        cacheTimeout => {
            tab => "display",
            fieldType => "interval",
            defaultValue => 3600,
            uiLevel => 5,
            label => $i18n->get("cache timeout", 'Asset_Snippet'),
            hoverHelp => $i18n->get("cache timeout help"),
        },
	};
	push(@{$definition}, {
		tableName=>'WeatherData',
		className=>'WebGUI::Asset::Wobject::WeatherData',
		assetName=>$i18n->get("assetName"),
		icon=>'weatherData.gif',
		autoGenerateForms=>1,
		properties=>$properties
	});
	return $class->SUPER::definition($session, $definition);
}

#-------------------------------------------------------------------

=head2 prepareView ( )

See WebGUI::Asset::prepareView() for details.

=cut

sub prepareView {
	my $self = shift;
	$self->SUPER::prepareView();
	my $template = WebGUI::Asset::Template->new($self->session, $self->get("templateId"));
    if (!$template) {
        WebGUI::Error::ObjectNotFound::Template->throw(
            error      => qq{Template not found},
            templateId => $self->get("templateId"),
            assetId    => $self->getId,
        );
    }
	$template->prepare($self->getMetaDataAsTemplateVariables);
	$self->{_viewTemplate} = $template;
}

#-------------------------------------------------------------------

=head2 view ( )

method called by the www_view method.  Returns a processed template
to be displayed within the page style

=cut

sub view {
	my $self = shift;
    my $session = $self->session;
	my %var;
    my $url = $self->session->url;
    
	if ($self->get("partnerId") ne "" && $self->get("licenseKey") ne "") {
        my $overrides = $self->fetchUserOverrides($self->getParent->getId);
        my $locations = $overrides->{locations} || $self->get('locations');
		foreach my $location (split("\n", $locations)) {
            my $cache = WebGUI::Cache->new($session, [$self->getId, $location]);
            my $loop_data;
            my $link_data = [];
            my $cached_data = $cache->get();
            if ($cached_data) {
                $loop_data = $cached_data->{locations};
                $link_data = $cached_data->{links} || [];
            }
            else {
                my $weather = Weather::Com::Finder->new({
                    'partner_id' => $self->get("partnerId"), 
                    'license'    => $self->get("licenseKey"),
                    'cache'		 => '/tmp',
                    });	
                next unless defined $weather;

                foreach my $foundLocation(@{$weather->find($location)}) {
                    my $current_conditions = $foundLocation->current_conditions;
                    my $conditions = $current_conditions->description;
                    $conditions    =~ s/\b(\w)/uc($1)/eg;
                    my $tempC      = $current_conditions->temperature;
                    my $tempF;
                    $tempF = sprintf("%.0f",(((9/5)*$tempC) + 32)) if($tempC);
                    my $icon = $current_conditions->icon || "na";

                    push @{$loop_data}, {
                        query       => $location,
                        cityState   => $foundLocation->name || $location,
                        sky         => $conditions || 'N/A',
                        tempF       => (defined $tempF)?$tempF:'N/A',
                        tempC       => (defined $tempC)?$tempC:'N/A',
                        smallIcon   => $url->extras("wobject/WeatherData/small_icons/".$icon.".png"),
                        mediumIcon  => $url->extras("wobject/WeatherData/medium_icons/".$icon.".png"),
                        largeIcon   => $url->extras("wobject/WeatherData/large_icons/".$icon.".png"),
                        iconUrl     => $url->extras("wobject/WeatherData/medium_icons/".$icon.".png"),
                        iconAlt     => $conditions,
                        last_fetch  => time(),
                    };
                    for my $lnk (@{$foundLocation->current_conditions->{WEATHER}{lnks}{link}} ) {
                        if (! $link_data) {
                            push @{ $link_data }, {
                                link_url    => $lnk->{l},
                                link_title  => $lnk->{t},
                            };
                        }
                    }
                }
                my $cache = WebGUI::Cache->new($session, [$self->getId, $location]);
                my $cached_data = {
                    locations => $loop_data,
                    links     => $link_data,
                };
                $cache->set($cached_data, $self->get('cacheTimeout'));
            }
            push @{$var{'ourLocations.loop'}}, @{ $loop_data };
            if (!$var{links_loop}) {
                $var{links_loop} = $link_data;
            }
		}
	}
	return $self->processTemplate(\%var, undef, $self->{_viewTemplate});
}

1;
