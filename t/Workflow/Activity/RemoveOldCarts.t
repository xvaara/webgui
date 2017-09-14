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
use WebGUI::Utility;
use WebGUI::Workflow::Activity::RemoveOldCarts;
use WebGUI::Shop::Cart;

use Test::More;
use Test::Deep;

plan tests => 6; # increment this value for each test you create

my $session = WebGUI::Test->session;
$session->user({userId => 3});

my $root = WebGUI::Asset->getRoot($session);
my $donation = $root->addChild({
    className => 'WebGUI::Asset::Sku::Donation',
    title     => 'test donation',
});
my $tag = WebGUI::VersionTag->getWorking($session);
$tag->commit;
WebGUI::Test->addToCleanup($tag);


my $cart1 = WebGUI::Shop::Cart->create($session);

my $session2 = WebGUI::Session->open(WebGUI::Test->root, WebGUI::Test->file);
$session2->user({userId => 3});
WebGUI::Test->addToCleanup($session2);
my $cart2 = WebGUI::Shop::Cart->create($session2);
$cart2->update({creationDate => time()-10000});

my @cartIds = $session->db->buildArray('select cartId from cart');
cmp_bag(
    \@cartIds,
    [ $cart1->getId, $cart2->getId ],
    'Made two carts for testing'
);

$donation->applyOptions({ price => 1111});
my $item1 = $cart1->addItem($donation);

$donation->applyOptions({ price => 2222});
my $item2 = $cart2->addItem($donation);

my @itemIds = $session->db->buildArray('select itemId from cartItem');
cmp_bag(
    \@itemIds,
    [ $item1->getId, $item2->getId ],
    'Made two items for testing'
);

my $workflow  = WebGUI::Workflow->create($session,
    {
        enabled    => 1,
        objectType => 'None',
        mode       => 'realtime',
    },
);
my $guard0 = cleanupGuard($workflow);
my $guard1 = cleanupGuard($cart1);
my $guard2 = cleanupGuard($cart2);
my $cartNuker = $workflow->addActivity('WebGUI::Workflow::Activity::RemoveOldCarts');
$cartNuker->set('cartTimeout', 3600);

my $instance1 = WebGUI::Workflow::Instance->create($session,
    {
        workflowId              => $workflow->getId,
        skipSpectreNotification => 1,
    }
);
WebGUI::Test->addToCleanup($instance1);

my $retVal;

$retVal = $instance1->run();
is($retVal, 'complete', 'cleanup: activity complete');
$retVal = $instance1->run();
is($retVal, 'done', 'cleanup: activity is done');
$instance1->delete('skipNotify');

@cartIds = $session->db->buildArray('select cartId from cart');
cmp_bag(
    \@cartIds,
    [ $cart1->getId, ],
    'Deleted 1 cart, the correct one'
);

@itemIds = $session->db->buildArray('select itemId from cartItem');
cmp_bag(
    \@itemIds,
    [ $item1->getId, ],
    'Deleted 1 item, the correct one'
);
