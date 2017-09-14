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
use Exception::Class;


my $toVersion = '7.10.19';
my $quiet; # this line required


my $session = start(); # this line required

# upgrade functions go here
addTicketLimitToBadgeGroup( $session );
fixBrokenCalendarFeedUrls ( $session );
removeUndergroundUserStyleTemplate ( $session );

finish($session); # this line required


#----------------------------------------------------------------------------
# Describe what our function does
#sub exampleFunction {
#    my $session = shift;
#    print "\tWe're doing some stuff here that you should know about... " unless $quiet;
#    # and here's our code
#    print "DONE!\n" unless $quiet;
#}


# Fix calendar feed urls that had adminId attached to them until they blew up
sub fixBrokenCalendarFeedUrls {
    my $session = shift;
    print "\tChecking all calendar feed URLs for adminId brokenness... " unless $quiet;
    my $getCalendar = WebGUI::Asset::Wobject::Calendar->getIsa($session);
    CALENDAR: while (1) {
        my $calendar = eval { $getCalendar->(); };
        next CALENDAR if Exception::Class->caught;
        last CALENDAR unless $calendar;
        FEED: foreach my $feed (@{ $calendar->getFeeds }) {
            $feed->{url} =~ s/adminId=[^;]{22};?//g;
            $feed->{url} =~ s/\?$//;
            $calendar->setFeed($feed->{feedId}, $feed);
        }
    }
    print "DONE!\n" unless $quiet;
}

#----------------------------------------------------------------------------
# Add a ticket limit to badges in a badge group
sub removeUndergroundUserStyleTemplate {
    my $session = shift;
    print "\tRemove Underground User Style template... " unless $quiet;
    if ($session->setting->get('userFunctionStyleId') eq 'zfDnOJgeiybz9vnmoEXRXA') {
        $session->setting->set('userFunctionStyleId', 'Qk24uXao2yowR6zxbVJ0xA');
    }
    my $underground_user = WebGUI::Asset->newByDynamicClass($session, 'zfDnOJgeiybz9vnmoEXRXA');
    if ($underground_user) {
        $underground_user->purge;
    }
    print "DONE!\n" unless $quiet;
}

#----------------------------------------------------------------------------
# Add a ticket limit to badges in a badge group
sub addTicketLimitToBadgeGroup {
    my $session = shift;
    print "\tAdd ticket limit to badge groups... " unless $quiet;
    # Make sure it hasn't been done already...
    my $columns = $session->db->buildHashRef('describe EMSBadgeGroup');
    use List::MoreUtils qw(any);
    if(!any { $_ eq 'ticketsPerBadge' } keys %{$columns}) {
        $session->db->write(q{
            ALTER TABLE EMSBadgeGroup ADD COLUMN `ticketsPerBadge` INTEGER
        });
    }
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
