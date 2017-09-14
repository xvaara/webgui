package WebGUI::Help::Asset_MapPoint;
use strict;

our $HELP = {

    'edit template' => {
        title => 'edit template',
        body  => '',
        isa   => [
            {   namespace => 'Asset_Template',
                tag       => 'template variables'
            },
            {   namespace => 'Asset_MapPoint',
                tag       => 'map point asset template variables'
            },
        ],
        fields    => [],
        variables => [
            { name      => 'form_header', required => 1, },
            { name      => 'form_footer', required => 1, },
            { name      => 'form_submit', },
            { name      => 'form_title', },
            { name      => 'form_synopsis', },
            { name      => 'form_storageIdPhoto', },
            { name      => 'currentPhoto', },
            { name      => 'form_website', },
            { name      => 'form_address1', },
            { name      => 'form_address2', },
            { name      => 'form_address3', },
            { name      => 'form_city', },
            { name      => 'form_region', },
            { name      => 'form_zipCode', },
            { name      => 'form_country', },
            { name      => 'form_phone', },
            { name      => 'form_fax', },
            { name      => 'form_email', },
            { name      => 'user defined variables', },
            { name      => 'form_isHidden', },
            { name      => 'form_isGeocoded', },
        ],
        related => []
    },

    'map point asset template variables' => {
        private => 1,
        title   => 'map point asset template variables',
        body    => '',
        isa     => [
            {   namespace => 'Asset',
                tag       => 'asset template asset variables'
            },
        ],
        fields    => [],
        variables => [
            { name      => 'latitude', },
            { name      => 'longitude', },
            { name      => 'storageIdPhoto', },
            { name      => 'website', },
            { name      => 'address1', },
            { name      => 'address2', },
            { name      => 'address3', },
            { name      => 'city', },
            { name      => 'region', },
            { name      => 'zipCode', },
            { name      => 'country', },
            { name      => 'phone', },
            { name      => 'fax', },
            { name      => 'email', },
            { name      => 'userDefined1', },
            { name      => 'userDefined2', },
            { name      => 'userDefined3', },
            { name      => 'userDefined4', },
            { name      => 'userDefined5', },
        ],
        related => []
    },

};

1;
