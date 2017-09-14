package WebGUI::Shop::AddressBook;

use strict;

use Class::InsideOut qw{ :std };
use JSON;
use WebGUI::Asset::Template;
use WebGUI::Exception::Shop;
use WebGUI::Form;
use WebGUI::International;
use WebGUI::Shop::Admin;
use WebGUI::Shop::Address;
use Scalar::Util qw/blessed/;

=head1 NAME

Package WebGUI::Shop::AddressBook;

=head1 DESCRIPTION

Managing addresses for commerce.

=head1 SYNOPSIS

 use WebGUI::Shop::AddressBook;

 my $book = WebGUI::Shop::AddressBook->new($session);

=head1 METHODS

These subroutines are available from this package:

=cut

readonly session => my %session;
private properties => my %properties;
private addressCache => my %addressCache;

#-------------------------------------------------------------------

=head2 addAddress ( address )

Adds an address to the address book.  Returns a reference to the WebGUI::Shop::Address
object that was created.  It does not trap exceptions, so any problems with creating
the object will be passed to the caller.

=head2 address

A hash reference containing address information.

=cut

sub addAddress {
    my ($self, $address) = @_;
    my $addressObj = WebGUI::Shop::Address->create( $self, $address);
    return $addressObj;
}

#-------------------------------------------------------------------

=head2 appendAddressFormVars ( $var, $properties, $prefix )

Add template variables for building a form to edit an address to an existing set of template variables.

=head3 $var

A hash ref of template variables.

=head3 $properties

A hash ref of properties to assign to as default to the form variables.

=head3 $prefix

An optional prefix to add to each variable name, and form name.

=cut

sub appendAddressFormVars {
    my ($self, $var, $prefix, $properties ) = @_;
    my $session   = $self->session;
    my $form      = $session->form;
    $properties ||= {};
    $prefix     ||= '';
    $var        ||= {};
    my $hasAddress = keys %{ $properties };
    for ( qw{ address1 address2 address3 label firstName lastName city state organization } ) {
        $var->{ $prefix . $_ . 'Field' } = WebGUI::Form::text( $session, {
            name            => $prefix . $_, 
            maxlength       => 35, 
            defaultValue    => $hasAddress ? $properties->{ $_ } : $form->get($prefix . $_),
        } );
    }
    $var->{ $prefix . 'countryField' } = 
        WebGUI::Form::country( $session,{
            name            => $prefix . 'country', 
            defaultValue    => $hasAddress ? $properties->{ country } : $form->get($prefix . 'country' ),
        } );
    $var->{ $prefix . 'codeField' } =
        WebGUI::Form::zipcode( $session, {
            name            => $prefix . 'code', 
            defaultValue    => $hasAddress ? $properties->{ code } : $form->get($prefix . 'code' ),
        } );
    $var->{ $prefix . 'phoneNumberField' } =
        WebGUI::Form::phone( $session, {
            name            => $prefix . 'phoneNumber', 
            defaultValue    => $hasAddress ? $properties->{ phoneNumber } : $form->get($prefix . 'phoneNumber' ),
        } );
    $var->{ $prefix . 'emailField' } =
        WebGUI::Form::email( $session, {
            name            => $prefix . 'email', 
            defaultValue    => $hasAddress ? $properties->{ email } : $form->get($prefix . 'email' ),
        } );
}

#-------------------------------------------------------------------

=head2 create ( session, userId )

Constructor. Creates a new address book for this user.

=head3 session

A reference to the current session.

=head3 userId

The userId for the user.  Throws an exception if it is Visitor.  Defaults to the session
user if omitted.

=cut

sub create {
    my ($class, $session, $userId) = @_;
    unless (defined $session && $session->isa("WebGUI::Session")) {
        WebGUI::Error::InvalidObject->throw(expected=>"WebGUI::Session", got=>(ref $session), error=>"Need a session.");
    }
    $userId ||= $session->user->userId;
    if ($userId eq '1') {
        WebGUI::Error::InvalidParam->throw(error=>"Visitor cannot have an address book.");
    }
    my $id = $session->db->setRow("addressBook", "addressBookId", {addressBookId=>"new", userId=>$userId}); 
    return $class->new($session, $id);
}

#-------------------------------------------------------------------

=head2 delete ()

Deletes this address book and all addresses contained in it.

=cut

sub delete {
    my ($self) = @_;
    my $myId   = id $self;
    foreach my $address (@{$self->getAddresses}) {
        delete $addressCache{$myId}{$address->getId};
        $address->delete;
    } 
    $self->session->db->write("delete from addressBook where addressBookId=?",[$self->getId]);
    undef $self;
    return undef;
}

#-------------------------------------------------------------------

=head2 formatCallbackForm ( callback )

Returns an HTML hidden form field with the callback JSON block properly escaped.

=head3 callback

A JSON string that holds the callback information.

=cut

sub formatCallbackForm {
    my ($self, $callback) = @_;
    $callback =~ s/"/'/g;
    return '<input type="hidden" name="callback" value="'.$callback.'" />';
}

#-------------------------------------------------------------------

=head2 get ( [ property ] )

Returns a duplicated hash reference of this object’s data.

=head3 property

Any field − returns the value of a field rather than the hash reference.  See the 
C<update> method.

=cut

sub get {
    my ($self, $name) = @_;
    if($name eq "profileAddressId" && !$properties{id $self}{$name}) {
        $properties{id $self}{$name} = $self->session->db->quickScalar(q{
            select addressId from address where addressBookId=? and isProfile=1
        },[$self->getId]);
    }
    if (defined $name) {
        return $properties{id $self}{$name};
    }
    my %copyOfHashRef = %{$properties{id $self}};
    return \%copyOfHashRef;
}

#-------------------------------------------------------------------

=head2 getAddress ( id )

Returns an address object.

=head3 id

An address object's unique id.

=cut

sub getAddress {
    my ($self, $addressId) = @_;
    my $id = id $self;
    unless (exists $addressCache{$id}{$addressId}) {
        $addressCache{$id}{$addressId} = WebGUI::Shop::Address->new($self, $addressId);
    }
    return $addressCache{$id}{$addressId};
}

#-------------------------------------------------------------------

=head2 getAddressByLabel ( label )

Returns an address object.

=head3 id

An address object's label, e.g. 'Home', 'Work'

=cut

sub getAddressByLabel {
    my ($self, $label) = @_;
    my $sql = q{
        SELECT addressId
        FROM   address
        WHERE  addressBookId = ?
        AND    label         = ?
    };
    my $id = $self->session->db->quickScalar($sql, [$self->getId, $label]);
    return $id && $self->getAddress($id);
}

#-------------------------------------------------------------------

=head2 getAddresses ( )

Returns an array reference of address objects that are in this book.

=cut

sub getAddresses {
    my ($self) = @_;
    my @addressObjects = ();
    my $addresses = $self->session->db->read("select addressId from address where addressBookId=?",[$self->getId]);
    while (my ($addressId) = $addresses->array) {
        push(@addressObjects, $self->getAddress($addressId));
    }
    return \@addressObjects;
}

#-------------------------------------------------------------------

=head2 getDefaultAddress ()

Returns the default address for this address book if there is one. Otherwise throws a WebGUI::Error::ObjectNotFound exception.

=cut

sub getDefaultAddress {
    my ($self) = @_;
    my $id = $self->get('defaultAddressId');
    if ($id ne '') {
        my $address = eval { $self->getAddress($id) };
        my $e;
        if ($e = WebGUI::Error->caught('WebGUI::Error::ObjectNotFound')) {
            $self->update({defaultAddressId=>''});
            $e->rethrow;
        }
        elsif ($e = WebGUI::Error->caught) {
            $e->rethrow;
        }
        else {
            return $address;
        }
    }
    WebGUI::Error::ObjectNotFound->throw(error=>"No default address.");
}

#-------------------------------------------------------------------

=head2 getProfileAddress ()

Returns the profile address for this address book if there is one. Otherwise throws a WebGUI::Error::ObjectNotFound exception.

=cut

sub getProfileAddress {
    my ($self) = @_;
    my $id = $self->get('profileAddressId');
    if ($id ne '') {
        my $address = eval { $self->getAddress($id) };
        my $e;
        if ($e = WebGUI::Error->caught('WebGUI::Error::ObjectNotFound')) {
            $e->rethrow;
        }
        elsif ($e = WebGUI::Error->caught) {
            $e->rethrow;
        }
        else {
            return $address;
        }
    }
    WebGUI::Error::ObjectNotFound->throw(error=>"No profile address.");
}

#-------------------------------------------------------------------

=head2 getProfileAddressMappings ( )

Class or object method which returns the profile address field mappings

=cut

sub getProfileAddressMappings {
    return {
        homeAddress => 'address1',
        homeCity    => 'city',
        homeState   => 'state',
        homeZip     => 'code',
        homeCountry => 'country',
        homePhone   => 'phoneNumber',
        email       => 'email',
        firstName   => 'firstName',
        lastName    => 'lastName'
    }
}

#-------------------------------------------------------------------

=head2 getId ()

Returns the unique id for this addressBook.

=cut

sub getId {
    my ($self) = @_;
    return $self->get("addressBookId");
}

#-------------------------------------------------------------------

=head2 missingFields ( $address ) 

Returns a list of missing, required fields in this address.

=head3 $address

An address.  If it's an WebGUI::Shop::Address object, it will use the data
from it.  Otherwise, it will assume that $address is just a hashref.

=cut

sub missingFields {
    my $self    = shift;
    my $address = shift;
    my $addressData;
    if (blessed $address && $address->isa('WebGUI::Shop::Address')) {
        $addressData = $address->get();
    }
    else {
        $addressData = $address;
    }
    my @missingFields = ();
    FIELD: foreach my $field (qw/firstName lastName address1 city state code country phoneNumber/) {
        push @missingFields, $field if $addressData->{$field} eq '';
    }
    return @missingFields;
}

#-------------------------------------------------------------------

=head2 new ( session, addressBookId )

Constructor.  Instanciates an addressBook based upon a addressBookId.

=head3 session

A reference to the current session.

=head3 addressBookId

The unique id of an address book to instanciate.

=cut

sub new {
    my ($class, $session, $addressBookId) = @_;
    unless (defined $session && $session->isa("WebGUI::Session")) {
        WebGUI::Error::InvalidObject->throw(expected=>"WebGUI::Session", got=>(ref $session), error=>"Need a session.");
    }
    unless (defined $addressBookId) {
        WebGUI::Error::InvalidParam->throw(error=>"Need an addressBookId.");
    }
    my $addressBook = $session->db->quickHashRef('select * from addressBook where addressBookId=?', [$addressBookId]);
    if ($addressBook->{addressBookId} eq "") {
        WebGUI::Error::ObjectNotFound->throw(error=>"No such address book.", id=>$addressBookId);
    }
    my $self = register $class;
    my $id        = id $self;
    $session{ $id }   = $session;
    $properties{ $id } = $addressBook;
    return $self;
}

#-------------------------------------------------------------------

=head2 newByUserId ( session, userId )

Constructor. Creates a new address book for this user if they don't have one.  In any case returns a reference to the address book.

=head3 session

A reference to the current session.

=head3 userId

The userId for the user.  Throws an exception if it is Visitor.  Defaults to the session
user if omitted.

=cut

sub newByUserId {
    my ($class, $session, $userId) = @_;
    unless (defined $session && $session->isa("WebGUI::Session")) {
        WebGUI::Error::InvalidObject->throw(expected=>"WebGUI::Session", got=>(ref $session), error=>"Need a session.");
    }
    $userId ||= $session->user->userId;
    if ($userId eq '1') {
        WebGUI::Error::InvalidParam->throw(error=>"Visitor cannot have an address book.");
    }
    
    # check to see if this user or his session already has an address book
    my @ids = $session->db->buildArray("select addressBookId from addressBook where userId=?",[$userId]);
    if (scalar(@ids) > 0) {
        my $book = $class->new($session, $ids[0]);
        
        # merge others if needed
        if (scalar(@ids) > 1) {
            # it's attached to the session or we have too many so lets merge them
            shift @ids;
            foreach my $id (@ids) {
                my $oldbook = $class->new($session, $id);
                foreach my $address (@{$oldbook->getAddresses}) {
                    $address->update({addressBookId=>$book->getId});
                }
                $oldbook->delete;
            }
        }
        return $book;
    }
    else {
        # nope create one for the user
        return $class->create($session,$userId);
    }
}


#-------------------------------------------------------------------

=head2 processAddressForm ( $prefix )

Process the current set of form variables for any belonging to the address book.  Returns
a hash ref of address information.

=head3 $prefix

An optional prefix to be added to each form variable.

=cut

sub processAddressForm {
    my ($self, $prefix) = @_;
    $prefix  ||= '';
    my $form   = $self->session->form;
    my %addressData = (
        label           => $form->get($prefix . "label") || '',
        firstName       => $form->get($prefix . "firstName") || '',
        lastName        => $form->get($prefix . "lastName") || '',
        address1        => $form->get($prefix . "address1") || '',
        address2        => $form->get($prefix . "address2") || '',
        address3        => $form->get($prefix . "address3") || '',
        city            => $form->get($prefix . "city") || '',
        state           => $form->get($prefix . "state") || '',
        code            => $form->get($prefix . "code",        "zipcode") || '',
        country         => $form->get($prefix . "country",     "country") || '',
        phoneNumber     => $form->get($prefix . "phoneNumber", "phone") || '',
        email           => $form->get($prefix . "email",       "email") || '',
        organization    => $form->get($prefix . "organization") || '',
    );

    ##Label is optional in the form, but required for the UI and API.
    ##Use the first address line in its place if it's missing
    $addressData{label} = $addressData{address1} if ! $addressData{label};
    return %addressData;
}

#-------------------------------------------------------------------

=head2 update ( properties )

Sets properties in the addressBook

=head3 properties

A hash reference that contains one of the following:

=head4 userId

Assign the user that owns this address book.

=head4 defaultAddressId

The id of the address to be made the default for this address book.

=cut

sub update {
    my ($self, $newProperties) = @_;
    my $id = id $self;
    foreach my $field (qw(userId defaultAddressId)) {
        $properties{$id}{$field} = (exists $newProperties->{$field}) ? $newProperties->{$field} : $properties{$id}{$field};
    }
 
    my %postProperties = %{$properties{$id}};
    delete $postProperties{profileAddressId};
    $self->session->db->setRow("addressBook","addressBookId",\%postProperties);
}

#-------------------------------------------------------------------

=head2 uncache (  )

Deletes the addressBook cache

=cut

sub uncache {
    my $self      = shift;
    delete $addressCache{id $self};
}


#-------------------------------------------------------------------

=head2 www_ajaxGetAddress ( )

Gets a JSON object representing the address given by the addressId form
parameter

=cut

sub www_ajaxGetAddress {
    my $self    = shift;
    my $session = $self->session;
    $session->http->setMimeType('text/plain');

    my $addressId = $session->form->get('addressId');
    my $address   = $self->getAddress($addressId) or return;
    return JSON->new->encode($address->get);
}

#-------------------------------------------------------------------

=head2 www_ajaxSave ( )

Saves an address book entry

=cut

sub www_ajaxSave {
    my $self    = shift;
    my $session = $self->session;
    my $address = JSON->new->decode($session->form->get('address'));
    my $obj     = $self->getAddressByLabel($address->{label});
    if ($obj) {
        $obj->update($address);
    }
    else {
        $obj = $self->addAddress($address);
    }
    $session->http->setMimeType('text/plain');
    return $obj->getId;
}

#-------------------------------------------------------------------

=head2 www_ajaxSearch ( )

Gets a JSON object with addresses returned based on the search
parameters from the form.

=cut

sub www_ajaxSearch {
    my $self    = shift;
    my $session = $self->session;
    my $form    = $session->form;

    my $name      = $form->get('name');
    my $fields = {
        firstName       => (split(" ",$name))[0] || "",
        lastName        => (split(" ",$name))[1] || "",
        organization    => $form->get('organization') || "",
        address1        => $form->get('address1') || "",
        address2        => $form->get('address2') || "",
        address3        => $form->get('address3') || "",
        city            => $form->get('city') || "",
        state           => $form->get('state') || "",
        code            => $form->get('zipcode') || "",
        country         => $form->get('country') || "",
        email           => $form->get('email') || "",
        phoneNumber     => $form->get('phone') || "",
    };

    my $clause = [];
    my $params = [];

    foreach my $field (keys %$fields) {
        my $field_value = $fields->{$field};
        if($field_value) {
            $field       = $session->db->dbh->quote_identifier($field);
            $field_value = $field_value."%";
            push(@$clause,qq{$field like ?});
            push(@$params,$field_value);
        }
    }

    my $admin = WebGUI::Shop::Admin->new($session);
    unless ($session->user->isAdmin || $admin->canManage || $admin->isCashier) {
        push(@$clause,qq{users.userId=?});
        push(@$params,$session->user->getId);
    }

    my $where  = "";
    $where = "where ".join(" and ",@$clause) if scalar(@$clause);

    my $query = qq{
        select
            address.*,
            users.username
        from
            address
            join addressBook on address.addressBookId = addressBook.addressBookId
            join users on addressBook.userId = users.userId
        $where
        limit 3
    };

    my $sth = $session->db->read($query,$params);
    my $var = [];
    while (my $hash = $sth->hashRef) {
        push(@$var,$hash);
    }

    $session->http->setMimeType('text/plain');
    return JSON->new->encode($var);
}

#-------------------------------------------------------------------

=head2 www_deleteAddress ( )

Deletes an address from the book.

=cut

sub www_deleteAddress {
    my $self = shift;
    my $address = $self->getAddress($self->session->form->get("addressId"));
    if (defined $address && !$address->isProfile) {
        $address->delete;
    }
    return $self->www_view;
}

#-------------------------------------------------------------------

=head2 www_defaultAddress ( )

Makes an address be the default.

=cut

sub www_defaultAddress {
    my $self = shift;
    $self->update({defaultAddressId=>$self->session->form->get("addressId")});
    return $self->www_view;
}

#-------------------------------------------------------------------

=head2 www_editAddress ()

Allows a user to edit an address in their address book.

=cut

sub www_editAddress {
    my ($self, $error) = @_;
    my $session     = $self->session;
    my $form        = $session->form;
    my $i18n        = WebGUI::International->new($session, "Shop");
    my $properties  = {};

    # Get address if available and extract address data
    my $address = eval{$self->getAddress($form->get("addressId"))};
    if (WebGUI::Error->caught) {
        $address    = undef;
    }
    else {
        $properties = $address->get;
    }

    # Replace address data with profile information if one of the copyFrom buttons is clicked.
    my $copyFrom = $form->process( 'copyFrom' );
    if ( $copyFrom eq 'work' || $copyFrom eq 'home' ) {
        my $user = $session->user;

        $properties->{ address1     } = $user->profileField( $copyFrom . 'Address' );
        $properties->{ firstName    } = $user->profileField( 'firstName' );
        $properties->{ lastName     } = 
            join ' ', $user->profileField( 'middleName' ), $user->profileField( 'lastName' );
        $properties->{ city         } = $user->profileField( $copyFrom . 'City'     );
        $properties->{ state        } = $user->profileField( $copyFrom . 'State'    );
        $properties->{ country      } = $user->profileField( $copyFrom . 'Country'  );
        $properties->{ code         } = $user->profileField( $copyFrom . 'Zip'      );
        $properties->{ phoneNumber  } = $user->profileField( $copyFrom . 'Phone'    );
        $properties->{ email        } = $user->profileField( 'email' );
        $properties->{ organization } = $user->profileField( 'workName' ) if $copyFrom eq 'work';
    }

    # Setup tmpl_vars
    my $var = {
        %{ $properties },
        error               => $error,
        formHeader          => 
            WebGUI::Form::formHeader($session)
            . $self->formatCallbackForm( $form->get('callback') )
            . WebGUI::Form::hidden($session, { name => 'shop',      value => 'address'               } )
            . WebGUI::Form::hidden($session, { name => 'method',    value => 'editAddressSave'       } )
            . WebGUI::Form::hidden($session, { name => 'addressId', value => $form->get('addressId') } ),
        saveButton          => WebGUI::Form::submit($session),
        formFooter          => WebGUI::Form::formFooter($session),
    };

    # Add buttons for copying address data from the user's profile.
    for ( qw{ work home } ) {
        my $what = lcfirst $_;
        $var->{ 'copyFrom' . $what . 'Button' } =
            WebGUI::Form::formHeader( $session )
            . $self->formatCallbackForm( $form->get('callback') )
            . WebGUI::Form::hidden( $session, { name => 'shop',       value => 'address'        } )
            . WebGUI::Form::hidden( $session, { name => 'method',     value => 'editAddress'    } )
            . WebGUI::Form::hidden( $session, { name => 'copyFrom',   value => $_               } )
            . WebGUI::Form::hidden( $session, { name => 'addressId',  value => $address ? $address->getId : '' } )
            . WebGUI::Form::submit( $session, { value => $i18n->get("copy from $_ address") } )
            . WebGUI::Form::formFooter( $session ), 
    };

    # Add form elements for each field to the tmpl_vars
    for ( qw{ address1 address2 address3 label firstName lastName city state organization } ) {
        $var->{ $_ . 'Field' } = WebGUI::Form::text( $session, {
            name            => $_, 
            maxlength       => 35, 
            defaultValue    => $form->get( $_ ) || $properties->{ $_ }
        } );
    }
    $var->{ countryField } = 
        WebGUI::Form::country( $session,{
            name            => 'country', 
            defaultValue    => $form->get('country') || $properties->{ country }
        } );
    $var->{ codeField } =
        WebGUI::Form::zipcode( $session, {
            name            => 'code', 
            defaultValue    => $form->get('code') || $properties->{ code }
        } );
    $var->{ phoneNumberField } =
        WebGUI::Form::phone( $session, {
            name            => 'phoneNumber', 
            defaultValue    => $form->get('phoneNumber') || $properties->{ phoneNumber }
        } );
    $var->{ emailField } =
        WebGUI::Form::email( $session, {
            name            => 'email', 
            defaultValue    =>$form->get('email') || $properties->{ email }
        } );

    my $template = WebGUI::Asset::Template->new( $session, $session->setting->get('shopAddressTemplateId') );
    $template->prepare;

    return $session->style->userStyle( $template->process( $var ) );
}

#-------------------------------------------------------------------

=head2 www_editAddressSave ()

Saves the address. If there is a problem generates www_editAddress() with an error message. Otherwise returns www_view().

=cut

sub www_editAddressSave {
    my $self = shift;
    my $form = $self->session->form;
    my %addressData = $self->processAddressForm();
    my @missingFields = $self->missingFields(\%addressData);
    if (@missingFields) {
        my $i18n = WebGUI::International->new($self->session, "Shop");
        my $missingField = pop @missingFields;
        my $label = $missingField eq 'label'        ? $i18n->get('label')
                  : $missingField eq 'firstName'    ? $i18n->get('firstName')
                  : $missingField eq 'lastName'     ? $i18n->get('lastName')
                  : $missingField eq 'address1'     ? $i18n->get('address')
                  : $missingField eq 'city'         ? $i18n->get('city')
                  : $missingField eq 'state'        ? $i18n->get('state')
                  : $missingField eq 'country'      ? $i18n->get('country')
                  : $missingField eq 'phoneNumber'  ? $i18n->get('phone number')
                  : '' ;
        if ($label) {
            return $self->www_editAddress(sprintf($i18n->get('is a required field'), $label));
        }
    }
    if ($form->get('addressId') eq '') {
        $self->addAddress(\%addressData);
    }
    else {
        my $addressId = $form->get('addressId');
        my $address   = $self->getAddress($addressId);
        $address->update(\%addressData);
        if($address->isProfile) {
            my $u = WebGUI::User->new($self->session, $self->get("userId"));
            my $address_mappings = $self->getProfileAddressMappings;
            foreach my $field (keys %$address_mappings) {
                my $addr_field = $address_mappings->{$field};
                $u->profileField($field,$address->get($addr_field));
            }
        }
    }

    #profile fields updated in WebGUI::Shop::Address->update
    return $self->www_view;
}


#-------------------------------------------------------------------

=head2 www_view

Displays the current user's address book.

=cut

sub www_view {
    my $self = shift;
    my $session = $self->session;
    my $form = $session->form;
    my $callback = $form->get('callback');
    $callback =~ s/'/"/g;
    $callback = JSON->new->decode($callback);
    my $callbackForm = '';
    foreach my $param (@{$callback->{params}}) {
        $callbackForm .= WebGUI::Form::hidden($session, {name=>$param->{name}, value=>$param->{value}});
    }
    my $i18n = WebGUI::International->new($session, "Shop");
    my @addresses = ();
    my @availableAddresses = @{ $self->getAddresses };
    if (! @availableAddresses ) {
        return $self->www_editAddress;
    }
    foreach my $address (@availableAddresses) {

        push(@addresses, {
            %{$address->get},
            address         => $address->getHtmlFormatted,
            isDefault       => ($self->get('defaultAddressId') eq $address->getId),
            deleteButton    => $address->get("isProfile") ? undef : WebGUI::Form::formHeader( $session )
                . WebGUI::Form::hidden( $session, { name => 'shop',      value => 'address'         } )
                . WebGUI::Form::hidden( $session, { name => 'method',    value => 'deleteAddress'   } )
                . WebGUI::Form::hidden( $session, { name => 'addressId', value => $address->getId   } )
                . $self->formatCallbackForm( $form->get('callback') )
                . WebGUI::Form::submit( $session, { value => $i18n->get('delete')                   } )
                . WebGUI::Form::formFooter( $session ),
            editButton      => 
                WebGUI::Form::formHeader( $session )
                . WebGUI::Form::hidden( $session, { name => 'shop',      value => 'address'         } )
                . WebGUI::Form::hidden( $session, { name => 'method',    value => 'editAddress'     } )
                . WebGUI::Form::hidden( $session, { name => 'addressId', value => $address->getId   } )
                . $self->formatCallbackForm( $form->get('callback') )
                . WebGUI::Form::submit( $session, { value => $i18n->get('edit')                     } )
                . WebGUI::Form::formFooter( $session ),
            defaultButton      => 
                WebGUI::Form::formHeader( $session )
                . WebGUI::Form::hidden( $session, { name => 'shop',       value => 'address'        } )
                . WebGUI::Form::hidden( $session, { name => 'method',     value => 'defaultAddress' } )
                . WebGUI::Form::hidden( $session, { name => 'addressId',  value => $address->getId  } )
                . $self->formatCallbackForm( $form->get('callback') )
                . WebGUI::Form::submit( $session, { value => $i18n->get('default')                  } )
                . WebGUI::Form::formFooter( $session ),
            useButton       => 
                WebGUI::Form::formHeader( $session, { action => $callback->{url} } )
                . $callbackForm
                . WebGUI::Form::hidden( $session, { name => 'addressId',  value => $address->getId  } )
                . WebGUI::Form::submit( $session, { value => $i18n->get('use this address')         } )
                . WebGUI::Form::formFooter( $session ),
            });
    }
    my %var = (
        addresses => \@addresses,
        addButton => WebGUI::Form::formHeader($session)
                    .WebGUI::Form::hidden($session, {name=>"shop", value=>"address"})
                    .WebGUI::Form::hidden($session, {name=>"method", value=>"editAddress"})
                    .$self->formatCallbackForm($form->get('callback'))
                    .WebGUI::Form::submit($session, {value=>$i18n->get("add a new address")})
                    .WebGUI::Form::formFooter($session),
        );
    my $template = WebGUI::Asset::Template->new($session, $session->setting->get("shopAddressBookTemplateId"));
    $template->prepare;
    return $session->style->userStyle($template->process(\%var));
}

1;

