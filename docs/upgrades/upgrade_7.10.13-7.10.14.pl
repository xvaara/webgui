#!/usr/bin/env perl

#-------------------------------------------------------------------
# WebGUI is Copyright 2001-2009 Plain Black Corporation.
#-------------------------------------------------------------------
# Please read the legal notices (docs/legal.txt) and the license
# (docs/license.txt) that came with this distribution before using
# this software.
#-------------------------------------------------------------------
# http://www.plainblack.com                     info@plainblack.com
#-------------------------------------------------------------------

our ($webguiRoot);

BEGIN {
    $webguiRoot = "../..";
    unshift (@INC, $webguiRoot."/lib");
}

use strict;
use Getopt::Long;
use WebGUI::Session;
use WebGUI::Storage;
use WebGUI::Asset;
use WebGUI::Asset::Wobject::Calendar;


my $toVersion = '7.10.14';
my $quiet; # this line required


my $session = start(); # this line required

# upgrade functions go here
addOrganizationsToTransaction($session);
removeDuplicateUndergroundStyleTemplates($session);
addRichEditToCarousel($session);
fixBadCalendarFeedStatus($session);

finish($session); # this line required


#----------------------------------------------------------------------------
# Describe what our function does
#sub exampleFunction {
#    my $session = shift;
#    print "\tWe're doing some stuff here that you should know about... " unless $quiet;
#    # and here's our code
#    print "DONE!\n" unless $quiet;
#}


#----------------------------------------------------------------------------
# Describe what our function does
sub fixBadCalendarFeedStatus {
    my $session = shift;
    print "\tFix the name of the iCal status field in all Calendar assets... " unless $quiet;
    # and here's our code
    my $fetch_calendar = WebGUI::Asset::Wobject::Calendar->getIsa($session);
    my $sth = $session->db->read('select assetId, revisionDate from Calendar');
    CALENDAR: while (my ($assetId, $revisionDate) = $sth->array) {
        my $calendar = eval {WebGUI::Asset->new($session, $assetId, 'WebGUI::Asset::Wobject::Calendar', $revisionDate)};
        next CALENDAR if !$calendar;
        FEED: foreach my $feed ( @{ $calendar->getFeeds } ) {
            my $status = delete $feed->{status};
            if (!exists $feed->{lastResult}) {
                $feed->{lastResult} = $status;
            }
            if (!exists $feed->{lastUpdated}) {
                $feed->{lastUpdated} = 'never';
            }
            $calendar->setFeed($feed->{feedId}, $feed);
        }
    }
    $sth->finish;
    print "DONE!\n" unless $quiet;
}

#----------------------------------------------------------------------------
# Describe what our function does
sub addOrganizationsToTransaction {
    my $session = shift;
    print "\tAdd organization fields to the addresses stored in the Transaction and TransactionItem... " unless $quiet;
    # and here's our code
    $session->db->write('ALTER TABLE transaction     ADD COLUMN shippingOrganization CHAR(35)');
    $session->db->write('ALTER TABLE transaction     ADD COLUMN paymentOrganization CHAR(35)');
    $session->db->write('ALTER TABLE transactionItem ADD COLUMN shippingOrganization CHAR(35)');
    print "DONE!\n" unless $quiet;
}

#----------------------------------------------------------------------------
# Describe what our function does
sub removeDuplicateUndergroundStyleTemplates {
    my $session = shift;
    print "\tRemove duplicate Underground Style templatess that were mistakenly added during the 7.10.13 upgrade... " unless $quiet;
    # and here's our code
    ASSETID: foreach my $assetId(qw/IeFioyemW2Ov-hFGFwD75A niYg8Da1sULTQnevZ8wYpw/) {
        my $asset = WebGUI::Asset->newByDynamicClass($session, $assetId);
        next ASSETID unless $asset;
        $asset->purge;  ##Kill it, crush it, grind its bits into dust.
    }
    print "DONE!\n" unless $quiet;
}

#----------------------------------------------------------------------------
# Describe what our function does
sub addRichEditToCarousel {
    my $session = shift;
    print "\tAdd RichEdit option to the Carousel... " unless $quiet;
    # and here's our code
    $session->db->write('ALTER TABLE Carousel ADD COLUMN richEditor CHAR(22) BINARY');
    $session->db->write(q!update Carousel set richEditor='PBrichedit000000000001'!);
    print "DONE!\n" unless $quiet;
}

# -------------- DO NOT EDIT BELOW THIS LINE --------------------------------

#----------------------------------------------------------------------------
# Add a package to the import node
sub addPackage {
    my $session     = shift;
    my $file        = shift;

    print "\tUpgrading package $file\n" unless $quiet;
    # Make a storage location for the package
    my $storage     = WebGUI::Storage->createTemp( $session );
    $storage->addFileFromFilesystem( $file );

    # Import the package into the import node
    my $package = eval {
        my $node = WebGUI::Asset->getImportNode($session);
        $node->importPackage( $storage, {
            overwriteLatest    => 1,
            clearPackageFlag   => 1,
            setDefaultTemplate => 1,
        } );
    };

    if ($package eq 'corrupt') {
        die "Corrupt package found in $file.  Stopping upgrade.\n";
    }
    if ($@ || !defined $package) {
        die "Error during package import on $file: $@\nStopping upgrade\n.";
    }

    return;
}

#-------------------------------------------------
sub start {
    my $configFile;
    $|=1; #disable output buffering
    GetOptions(
        'configFile=s'=>\$configFile,
        'quiet'=>\$quiet
    );
    my $session = WebGUI::Session->open($webguiRoot,$configFile);
    $session->user({userId=>3});
    my $versionTag = WebGUI::VersionTag->getWorking($session);
    $versionTag->set({name=>"Upgrade to ".$toVersion});
    return $session;
}

#-------------------------------------------------
sub finish {
    my $session = shift;
    updateTemplates($session);
    my $versionTag = WebGUI::VersionTag->getWorking($session);
    $versionTag->commit;
    $session->db->write("insert into webguiVersion values (".$session->db->quote($toVersion).",'upgrade',".time().")");
    $session->close();
}

#-------------------------------------------------
sub updateTemplates {
    my $session = shift;
    return undef unless (-d "packages-".$toVersion);
    print "\tUpdating packages.\n" unless ($quiet);
    opendir(DIR,"packages-".$toVersion);
    my @files = readdir(DIR);
    closedir(DIR);
    my $newFolder = undef;
    foreach my $file (@files) {
        next unless ($file =~ /\.wgpkg$/);
        # Fix the filename to include a path
        $file       = "packages-" . $toVersion . "/" . $file;
        addPackage( $session, $file );
    }
}

#vim:ft=perl
