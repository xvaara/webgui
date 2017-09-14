#-------------------------------------------------------------------
# WebGUI is Copyright 2001-2009 Plain Black Corporation.
#-------------------------------------------------------------------
# Please read the legal notices (docs/legal.txt) and the license
# (docs/license.txt) that came with this distribution before using
# this software.
#-------------------------------------------------------------------
# http://www.plainblack.com                     info@plainblack.com
#-------------------------------------------------------------------

use FindBin;
use strict;
use lib "$FindBin::Bin/../lib";

use WebGUI::Test;
use WebGUI::Session;
use WebGUI::Asset::Template;
use Exception::Class;
use Test::More tests => 59; # increment this value for each test you create
use Test::Deep;
use Data::Dumper;
use Test::Exception;
use JSON qw{ from_json };

my $session = WebGUI::Test->session;
my $default = $session->config->get('defaultTemplateParser');
my $ht      = 'WebGUI::Asset::Template::HTMLTemplate';

my $list = WebGUI::Asset::Template->getList($session);
cmp_deeply($list, {}, 'getList with no classname returns an empty hashref');

my $tmplText = " <tmpl_var variable> <tmpl_if conditional>true</tmpl_if> <tmpl_loop loop>XY</tmpl_loop> ";
my %var = (
	variable=>"AAAAA",
	conditional=>1,
	loop=>[{},{},{},{},{}]
	);
my $output = WebGUI::Asset::Template->processRaw($session,$tmplText,\%var, $ht);
ok($output =~ m/\bAAAAA\b/, "processRaw() - variables");
ok($output =~ m/true/, "processRaw() - conditionals");
ok($output =~ m/\s(?:XY){5}\s/, "processRaw() - loops");

my $importNode = WebGUI::Asset::Template->getImportNode($session);

my $template = $importNode->addChild({className=>"WebGUI::Asset::Template"});
is($template->get('parser'), $default, "default parser is $default");

$template = $importNode->addChild({className=>"WebGUI::Asset::Template", title=>"test", url=>"testingtemplates", template=>$tmplText, namespace=>'WebGUI Test Template',parser=>$ht});
isa_ok($template, 'WebGUI::Asset::Template', "creating a template");


$var{variable} = "BBBBB";
$output = $template->process(\%var);
ok($output =~ m/\bBBBBB\b/, "process() - variables");
ok($output =~ m/true/, "process() - conditionals");
ok($output =~ m/\b(?:XY){5}\b/, "process() - loops");

# See if template listens the Accept header
my $request = $session->request;
my $in      = $request->headers_in;
my $out     = $request->headers_out;
$in->{Accept} = 'application/json';

my $json = $template->process(\%var);
my $andNowItsAPerlHashRef = eval { from_json( $json ) };
ok( !$@, 'Accept = json, JSON is returned' );
cmp_deeply( \%var, $andNowItsAPerlHashRef, 'Accept = json, The correct JSON is returned' );

# Done, so remove the json Accept header.
delete $session->request->headers_in->{Accept};

# Testing the stuff-your-variables-into-the-body-with-delimiters header
my $oldUser = $session->user;

# log in as admin so we pass canEdit
$session->user({ userId => 3 });
my $hname = 'X-Webgui-Template-Variables';
$in->{$hname} = $template->getId;

# processRaw sets some session variables (including username), so we need to
# re-do it.
WebGUI::Asset::Template->processRaw($session,$tmplText,\%var);

# This has to get called to set up the stow good and proper
WebGUI::Asset::Template->processVariableHeaders($session);

$template->process(\%var);

my $output = WebGUI::Asset::Template->getVariableJson($session);

delete $in->{$hname};
my $start = delete $out->{"$hname-Start"};
my $end   = delete $out->{"$hname-End"};
my ($json) = $output =~ /\Q$start\E(.*)\Q$end\E/;
$andNowItsAPerlHashRef = eval { from_json( $json ) };
cmp_deeply( $andNowItsAPerlHashRef, \%var, "$hname: json returned correctly" )
    or diag "output: $output";

$session->user({ user => $oldUser });

# done testing the header stuff

my $newList = WebGUI::Asset::Template->getList($session, 'WebGUI Test Template');
ok(exists $newList->{$template->getId}, 'Uncommitted template exists returned from getList');

my $newList2 = WebGUI::Asset::Template->getList($session, 'WebGUI Test Template', "assetData.status='approved'");
ok(!exists $newList2->{$template->getId}, 'extra clause to getList prevents uncommitted template from being displayed');

$template->update({isDefault=>1});
is($template->get('isDefault'), 1, 'isDefault set to 1');
my $templateCopy = $template->duplicate();
is($templateCopy->get('isDefault'), 0, 'isDefault set to 0 on copy');

my $template3 = $importNode->addChild({
    className => "WebGUI::Asset::Template",
    title     => 'headBlock test',
    headBlock => "tag1 tag2 tag3",
    template  => "this is a template",
    parser    => $ht,
}, undef, time()-5);

ok(!$template3->get('headBlock'),    'headBlock is empty');
is($template3->get('extraHeadTags'), 'tag1 tag2 tag3', 'extraHeadTags contains headBlock info');

my @atts = (
    {type => 'headScript', url => 'foo'},
    {type => 'headScript', url => 'bar'},
    {type => 'stylesheet', url => 'style'},
    {type => 'bodyScript', url => 'body'},
);

$template3->update({ attachmentsJson => JSON->new->encode( \@atts ) });
my $att3 = $template3->getAttachments('headScript');
is($att3->[0]->{url}, 'foo', 'has foo');
is($att3->[1]->{url}, 'bar', 'has bar');
is(@$att3, 2, 'proper size');

$template3->prepare;
ok(exists $session->style->{_link}->{style}, 'style in style');
ok(exists $session->style->{_javascript}->{$_}, "$_ in style") for qw(foo bar body);

# revision-ness of attachments

# sleep so the revisiondate isn't duplicated
#sleep 1;

my $template3dup = $template3->duplicate;
my @atts3dup = @{ $template3dup->getAttachments };
cmp_bag(
    [@atts3dup],
    [@atts],
    'attachments are duplicated'
) or diag( Dumper \@atts3dup );

my $template3rev = $template3->addRevision();
my $att4 = $template3rev->getAttachments('headScript');
is($att4->[0]->{url}, 'foo', 'rev has foo');
is($att4->[1]->{url}, 'bar', 'rev has bar');
is(@$att4, 2, 'rev is proper size');

$template3rev->update({ 
    attachmentsJson => JSON->new->encode([ @atts, {type => 'headScript', url => 'baz'} ]),
});
$att4 = $template3rev->getAttachments('headScript');
$att3 = $template3->getAttachments('headScript');
is($att3->[0]->{url}, 'foo', 'original still has foo');
is($att3->[1]->{url}, 'bar', 'original still has bar');
is(@$att3, 2, 'original does not have new thing');

is($att4->[0]->{url}, 'foo', 'rev still has foo');
is($att4->[1]->{url}, 'bar', 'rev still has bar');
is($att4->[2]->{url}, 'baz', 'rev does have new thing') or diag( $template3rev->get('attachmentsJson') );
is(@$att4, 3, 'rev is proper size');

$template3rev->addAttachments([{ url => 'box', type => 'headScript', }, { url => 'bux', type => 'headScript', }, ]);
cmp_deeply(
    [ map { $_->{url} } @{ $template3rev->getAttachments('headScript') } ],
    [qw/foo bar baz box bux/],
    'addAttachments appends to the end'
) or diag $template3rev->get('attachmentsJson');

$template3rev->removeAttachments(['box']);
cmp_deeply(
    [ map { $_->{url} } @{ $template3rev->getAttachments('headScript') } ],
    [qw/foo bar baz bux/],
    'removeAttachments will remove urls by exact URL match'
) or diag $template3rev->get('attachmentsJson');

$template3rev->removeAttachments(['bu']);
cmp_deeply(
    [ map { $_->{url} } @{ $template3rev->getAttachments('headScript') } ],
    [qw/foo bar baz bux/],
    '... checking that it is not treated like a wildcard'
) or diag $template3rev->get('attachmentsJson');

$template3rev->removeAttachments();
cmp_deeply(
    [ map { $_->{url} } @{ $template3rev->getAttachments('headScript') } ],
    [ ],
    '... checking that all attachments are removed'
) or diag $template3rev->get('attachmentsJson');

$template3rev->purgeRevision();

## Check how templates in the trash and clipboard are handled.

$session->asset($importNode);
$session->var->switchAdminOff;

my $trashTemplate = $importNode->addChild({
    className => "WebGUI::Asset::Template",
    title     => 'Trash template',
    template  => q|Trash Trash Trash Trash|,
    parser    => $ht,
});

$trashTemplate->trash;
is($trashTemplate->process, '', 'process: returns nothing when the template is in the trash, and admin mode is off');

$trashTemplate->cut;
is($trashTemplate->process, '', '... returns nothing when the template is in the trash, and admin mode is off');

$session->var->switchAdminOn;

$trashTemplate->trash;
is($trashTemplate->process, 'Template in trash', '... returns message when the template is in the trash, and admin mode is on');

$trashTemplate->cut;
is($trashTemplate->process, 'Template in clipboard', '... returns message when the template is in the trash, and admin mode is on');

$session->var->switchAdminOff;

# Check error logging for bad templates

my $brokenTemplate = $importNode->addChild({
    className => "WebGUI::Asset::Template",
    title     => 'Broken template',
    template  => q|<tmpl_if unclosedIf>If clause with no ending tag|,
    parser    => $ht,
});

WebGUI::Test->interceptLogging;
my $brokenOutput = $brokenTemplate->process({});
my $logError = $WebGUI::Test::logger_error;
my $brokenUrl = $brokenTemplate->getUrl;
my $brokenId  = $brokenTemplate->getId;
like($brokenOutput, qr/^There is a syntax error in this template/, 'process: returned error output contains boilerplate');
like($brokenOutput, qr/$brokenUrl/, '... and the template url');
like($brokenOutput, qr/$brokenId/, '... and the template id');
like($logError, qr/$brokenUrl/, 'process: logged error has the url');
like($logError, qr/$brokenId/, '... and the template id');
WebGUI::Test->restoreLogging;

WebGUI::Test->addToCleanup(WebGUI::VersionTag->getWorking($session));

my $userStyleTemplate = $importNode->addChild({
    className => "WebGUI::Asset::Template",
    title     => "user function style",
    url       => "ufs",
    template  => "user function style",
    namespace => 'WebGUI Test Template',
    parser    => $ht,
});

my $someOtherTemplate = $importNode->addChild({
    className => "WebGUI::Asset::Template",
    title     => "some other template",
    url       => "sot",
    template  => "some other template",
    namespace => 'WebGUI Test Template',
    parser    => $ht,
});

$session->setting->set('userFunctionStyleId', $userStyleTemplate->getId);

my $purgeCutTag = WebGUI::VersionTag->getWorking($session);
WebGUI::Test->addToCleanup($purgeCutTag);

is($session->setting->get('userFunctionStyleId'), $userStyleTemplate->getId, 'Setup for cut tests.');

$userStyleTemplate->cut;
is($session->setting->get('userFunctionStyleId'), 'PBtmpl0000000000000060', 'cut resets the user function style template to Fail Safe');

$userStyleTemplate->publish;
$session->setting->set('userFunctionStyleId', $userStyleTemplate->getId);
is($session->setting->get('userFunctionStyleId'), $userStyleTemplate->getId, 'Reset for purge test');

$userStyleTemplate->purge;
is($session->setting->get('userFunctionStyleId'), 'PBtmpl0000000000000060', 'purge resets the user function style template to Fail Safe');

#----------------------------------------------------------------------------
# Verify getParser
WebGUI::Test->originalConfig( 'defaultTemplateParser' );
WebGUI::Test->originalConfig( 'templateParsers' );
$session->config->set( 'templateParsers', [ 'WebGUI::Asset::Template::HTMLTemplateExpr' ] );
# Leaving out 'WebGUI::Asset::Template::TemplateToolkit' on purpose
$session->config->set( 'defaultTemplateParser', 'WebGUI::Asset::Template::HTMLTemplateExpr' );

my $class = 'WebGUI::Asset::Template';
dies_ok { $class->getParser( $session, '::HI::' ) } "Invalid parser dies";

isa_ok $class->getParser( $session ), 'WebGUI::Asset::Template::HTMLTemplateExpr', 'no parser passed in gets the default parser';

$session->config->delete( 'defaultTemplateParser' );
isa_ok $class->getParser( $session ), 'WebGUI::Asset::Template::HTMLTemplate', 'no parser passed and no default gets HTMLTemplate';
$session->config->set( 'defaultTemplateParser', 'WebGUI::Asset::Template::HTMLTemplateExpr' );

throws_ok 
    { $class->getParser( $session, 'WebGUI::Asset::Template::TemplateToolkit') } 
    'WebGUI::Error::NotInConfig',
    'Parser not in config dies';
isa_ok $class->getParser( $session, 'WebGUI::Asset::Template::HTMLTemplateExpr'), 'WebGUI::Asset::Template::HTMLTemplateExpr', 'parser in config is created';

{
use Test::MockObject::Extends;
my $mockparser = Test::MockObject->new->mock( process => sub { $@ = "failed" } );
my $mockTemplate = Test::MockObject::Extends->new( $class )
        ->mock( get => sub { return '' } )
        ->mock( session => sub { return $session } )
        ->mock( getParser => sub { return $mockparser } )
     ;
is $mockTemplate->process, 'failed', 'handle non-reference exceeption';
}

