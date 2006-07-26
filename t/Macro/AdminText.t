#-------------------------------------------------------------------
# WebGUI is Copyright 2001-2006 Plain Black Corporation.
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
use WebGUI::Macro::AdminText;
use WebGUI::Session;
use Data::Dumper;

my $session = WebGUI::Test->session;

use Test::More; # increment this value for each test you create

my $numTests = 4;

plan tests => $numTests;

my $output;

$output = WebGUI::Macro::AdminText::process($session, 'admin');
is($output, '', 'user is not admin');

$session->user({userId => 3});
$output = WebGUI::Macro::AdminText::process($session, 'admin');
is($output, '', 'user is admin, not in admin mode');

$session->var->switchAdminOn;
$output = WebGUI::Macro::AdminText::process($session, 'admin');
is($output, 'admin', 'admin in admin mode');

$session->var->switchAdminOff;
$output = WebGUI::Macro::AdminText::process($session, 'admin');
is($output, '', 'user is admin, not in admin mode');
