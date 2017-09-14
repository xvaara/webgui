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
use lib "$FindBin::Bin/../../lib";
use WebGUI::Test;
use WebGUI::Session;
use WebGUI::User;
use WebGUI::Group;
use WebGUI::Asset::Wobject::Collaboration;
use WebGUI::Asset::Post;
use WebGUI::Asset::Wobject::Layout;
use Data::Dumper;
use Test::More tests => 16; # increment this value for each test you create

my $session = WebGUI::Test->session;
my @addChildCoda = (undef, undef,
        {
            skipAutoCommitWorkflows => 1,
            skipNotification        => 1,
        }
);

# Do our work in the import node
my $node = WebGUI::Asset->getImportNode($session);

# grab a named version tag
my $versionTag = WebGUI::VersionTag->getWorking($session);
addToCleanup($versionTag);
$versionTag->set({name => 'Collaboration => groupToEditPost test'});

# place the collab system under a layout to ensure we're using the inherited groupIdEdit value
my $layout  = $node->addChild({className => 'WebGUI::Asset::Wobject::Layout'});

# set the layout as the current asset for the same reason
$session->asset($layout);

# finally, add the collab
my $collab  = $layout->addChild({
    className => 'WebGUI::Asset::Wobject::Collaboration',
    url       => 'collab',
});

$versionTag->commit;
$collab = $collab->cloneFromDb;
ok($session->id->valid($collab->get('getMailCronId')), 'commited CS has a cron job created for it');

# Test for a sane object type
isa_ok($collab, 'WebGUI::Asset::Wobject::Collaboration');

# Verify that the groupToEdit field exists
ok(defined $collab->get('groupToEditPost'), 'groupToEditPost field is defined');

# Verify sane defaults
cmp_ok($collab->get('groupToEditPost'), 'eq', $collab->get('groupIdEdit'), 'groupToEditPost defaults to groupIdEdit correctly');
is($collab->get('itemsPerFeed'), 25, 'itemsPerFeed is set to the default');

# finally, add the post to the collaboration system
my $props = {
    className   => 'WebGUI::Asset::Post::Thread',
    content     => 'hello, world!',
};
my $thread = $collab->addChild($props, @addChildCoda);
my $tag1 = WebGUI::VersionTag->getWorking($session);
$tag1->commit;
addToCleanup($tag1);

# Test for a sane object type
isa_ok($thread, 'WebGUI::Asset::Post::Thread');

$props = {
    className   => 'WebGUI::Asset::Post::Thread',
    content     => 'jello, world!',
};

my $thread2 = $collab->addChild($props, @addChildCoda);
my $tag2 = WebGUI::VersionTag->getWorking($session);
$tag2->commit;
addToCleanup($tag2);

my $rssitems = $collab->getRssFeedItems();
is(scalar @{ $rssitems }, 2, 'rssitems set to number of posts added');

note "AssetAspect tests";
is($collab->getRssFeedUrl,  '/collab?func=viewRss',  'getRssFeedUrl');
is($collab->getRdfFeedUrl,  '/collab?func=viewRdf',  'getRdfFeedUrl');
is($collab->getAtomFeedUrl, '/collab?func=viewAtom', 'getAtomFeedUrl');

note "Mail Cron job tests";
my $dupedCollab = $collab->duplicate();
addToCleanup(WebGUI::VersionTag->new($session, $dupedCollab->get('tagId')));
ok($dupedCollab->get('getMailCronId'), 'Duplicated CS has a cron job');
isnt($dupedCollab->get('getMailCronId'), $collab->get('getMailCronId'), '... and it is different from its source asset');

note "Thread and Post count tests";
$collab = $collab->cloneFromDb;
is $collab->get('threads'), 2, 'CS has 2 thread';
is $collab->get('replies'), 0, '... and no replies (posts)';

$thread2->archive();
$collab = $collab->cloneFromDb;
is $collab->get('threads'), 1, 'CS lost 1 thread due to archiving';

my $thread3 = $collab->addChild($props, @addChildCoda);
my $tag3 = WebGUI::VersionTag->getWorking($session);
$tag3->commit;
addToCleanup($tag3);
$collab = $collab->cloneFromDb;
is $collab->get('threads'), 2, '... added 1 thread';

