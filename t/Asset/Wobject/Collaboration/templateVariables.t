# vim:syntax=perl
#-------------------------------------------------------------------
# WebGUI is Copyright 2001-2009 Plain Black Corporation.
#-------------------------------------------------------------------
# Please read the legal notices (docs/legal.txt) and the license
# (docs/license.txt) that came with this distribution before using
# this software.
#------------------------------------------------------------------
# http://www.plainblack.com                     info@plainblack.com
#------------------------------------------------------------------

# Test the Collaboration system template variables
# 
#

use FindBin;
use strict;
use lib "$FindBin::Bin/../../../lib";
use WebGUI::Test; # Must use this before any other WebGUI modules
use Test::More;
use Test::Deep;
use Data::Dumper;
use WebGUI::Session;

#----------------------------------------------------------------------------
# Tests
plan tests => 23;        # Increment this number for each test you create

#----------------------------------------------------------------------------
# Init
my $session         = WebGUI::Test->session;
my @addChildArgs    = ( {skipAutoCommitWorkflows=>1, skipNotification => 1, } );
my $collab          = WebGUI::Asset->getImportNode( $session )->addChild({
    className        => 'WebGUI::Asset::Wobject::Collaboration',
    threadsPerPage   => 20,
    displayLastReply => 1,
});

my @threads = (
    $collab->addChild( {
        className       => 'WebGUI::Asset::Post::Thread',
        title           => "X - Foo",
        isSticky        => 0,
        ownerUserId     => 1,
    }, undef, 1, @addChildArgs),
    $collab->addChild( {
        className       => 'WebGUI::Asset::Post::Thread',
        title           => "X - Bar",
        isSticky        => 0,
        ownerUserId     => 3,
    }, undef, 2, @addChildArgs),
);

$_->setSkipNotification for @threads; # 100+ messages later...
my $versionTag = WebGUI::VersionTag->getWorking( $session );
$versionTag->commit;
WebGUI::Test->addToCleanup($versionTag);

my $templateVars;
my $posts;
$session->user({userId => 3});
$templateVars = $collab->getViewTemplateVars();

##Threads come in reverse order, most recent first
$posts = $templateVars->{post_loop};
is(  $posts->[1]->{'ownerUserId'}, 1, 'first post owned by visitor');
ok(  $posts->[1]->{'user.isVisitor'}, 'first post made by visitor');
ok(  $posts->[1]->{'hideProfileUrl'}, 'hide profile url, since post made by visitor');
ok(  $posts->[1]->{'lastReply.user.isVisitor'}, 'lastReply not made by visitor');
ok(  $posts->[1]->{'lastReply.hideProfileUrl'}, 'lastReply show profile url, since post not made by visitor, and user is not visitor');
is(  $posts->[0]->{'ownerUserId'}, 3, 'second post owned by admin');
ok( !$posts->[0]->{'user.isVisitor'}, 'first post made by visitor');
ok( !$posts->[0]->{'hideProfileUrl'}, 'show profile url, since post made by admin, and user is not visitor');
ok( !$posts->[0]->{'lastReply.user.isVisitor'}, 'lastReply not made by visitor');
ok( !$posts->[0]->{'lastReply.hideProfileUrl'}, 'lastReply show profile url, since post not made by visitor, and user is not visitor');

$session->user({userId => 1});
$templateVars = $collab->getViewTemplateVars();

##Threads come in reverse order, most recent first
$posts = $templateVars->{post_loop};
is(  $posts->[1]->{'ownerUserId'}, 1, 'first post owned by visitor');
ok(  $posts->[1]->{'user.isVisitor'}, 'first post made by visitor');
ok(  $posts->[1]->{'hideProfileUrl'}, 'hide profile url, since current user is visitor');
ok(  $posts->[1]->{'lastReply.user.isVisitor'}, 'lastReply not made by visitor');
ok(  $posts->[1]->{'lastReply.hideProfileUrl'}, 'lastReply hide profile url, since user is visitor');
is(  $posts->[0]->{'ownerUserId'}, 3, 'second post owned by admin');
ok( !$posts->[0]->{'user.isVisitor'}, 'first post made by visitor');
ok(  $posts->[0]->{'hideProfileUrl'}, 'hide profile url, and user is visitor');
ok( !$posts->[0]->{'lastReply.user.isVisitor'}, 'lastReply not made by visitor');
ok(  $posts->[0]->{'lastReply.hideProfileUrl'}, 'lastReply hide profile url, since user is visitor');
is(  $posts->[0]->{'lastReply.url'}, $threads[1]->getUrl.'?pn=1#id'.$threads[1]->getId, 'lastReply url has a query fragment prefixed by "id"');
is(  $posts->[0]->{'url'}, $threads[1]->getUrl.'#id'.$threads[1]->getId, 'url has a query fragment prefixed by "id"');


###################################################################
#
#isSecond, isThird, etc.
#
###################################################################

my @newThreads = ();
foreach my $index (1 .. 5) {
    $newThreads[$index] =  $collab->addChild( {
        className       => 'WebGUI::Asset::Post::Thread',
        title           => "X - Bar",
        isSticky        => 0,
        ownerUserId     => 3,
    }, undef, 2+$index, @addChildArgs);
    $newThreads[$index]->setSkipNotification;
}
my $vt2 = WebGUI::VersionTag->getWorking($session);
$vt2->commit;
addToCleanup($versionTag);

$session->user({userId => 3});
$templateVars = $collab->getViewTemplateVars();
my $indexVars;
foreach my $post (@{ $templateVars->{post_loop }}) {
    push @{$indexVars}, {
        isSecond => $post->{isSecond} ? 1 : 0,
        isThird  => $post->{isThird}  ? 1 : 0,
        isFourth => $post->{isFourth} ? 1 : 0,
        isFifth  => $post->{isFifth}  ? 1 : 0,
    };
}

cmp_deeply(
    $indexVars,
    [
        { isSecond => 0, isThird => 0, isFourth => 0, isFifth => 0, },
        { isSecond => 1, isThird => 0, isFourth => 0, isFifth => 0, },
        { isSecond => 0, isThird => 1, isFourth => 0, isFifth => 0, },
        { isSecond => 0, isThird => 0, isFourth => 1, isFifth => 0, },
        { isSecond => 0, isThird => 0, isFourth => 0, isFifth => 1, },
        { isSecond => 0, isThird => 0, isFourth => 0, isFifth => 0, },  ##No modulo
        { isSecond => 0, isThird => 0, isFourth => 0, isFifth => 0, },  ##No modulo
    ],
    'checking isSecond, isThird, isFourth, isFifth'
);
#vim:ft=perl
