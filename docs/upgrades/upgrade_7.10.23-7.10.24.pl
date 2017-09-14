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


my $toVersion = '7.10.24';
my $quiet; # this line required


my $session = start(); # this line required

# upgrade functions go here
addPALastLogTable($session);
addForkRedirect($session);
extendBucketName($session);
fixSurveyQuestionTypes($session);

finish($session); # this line required


#----------------------------------------------------------------------------
# Describe what our function does
sub addPALastLogTable {
    my $session = shift;
    print "\tAdd a table to keep track of additional Passive Analytics data... " unless $quiet;
    # and here's our code
    $session->db->write(<<EOSQL);
CREATE TABLE IF NOT EXISTS `PA_lastLog` (
`userId` char(22) CHARACTER SET utf8 COLLATE utf8_bin NOT NULL,
`assetId` char(22) CHARACTER SET utf8 COLLATE utf8_bin NOT NULL,
`sessionId` char(22) CHARACTER SET utf8 COLLATE utf8_bin NOT NULL,
`timeStamp` bigint(20) DEFAULT NULL,
`url` char(255) NOT NULL,
PRIMARY KEY (userId, sessionId)
) ENGINE=MyISAM DEFAULT CHARSET=utf8
EOSQL
    print "DONE!\n" unless $quiet;
}

#----------------------------------------------------------------------------
# Describe what our function does
sub addForkRedirect {
    my $session = shift;
    print "\tAdd a column to Fork to keep track of late generated redirect URLs... " unless $quiet;
    # and here's our code
    $session->db->write(<<EOSQL);
ALTER TABLE Fork add column redirect CHAR(255);
EOSQL
    print "DONE!\n" unless $quiet;
}

#----------------------------------------------------------------------------
# Describe what our function does
sub extendBucketName {
    my $session = shift;
    print "\tExtend the size of the bucket name in the bucketLog table for Passive Analytics... " unless $quiet;
    # and here's our code
    $session->db->write(<<EOSQL);
ALTER TABLE bucketLog CHANGE COLUMN Bucket Bucket CHAR(255)
EOSQL
    print "DONE!\n" unless $quiet;
}


#----------------------------------------------------------------------------
# Describe what our function does
sub fixSurveyQuestionTypes {
    my $session = shift;
    print "\tFix bad custom Question Types in the Survey... " unless $quiet;
    # and here's our code
    $session->db->write(<<EOSQL);
update Survey_questionTypes set answers="{}" where answers like 'HASH%';
EOSQL
    print "DONE!\n" unless $quiet;
}

#----------------------------------------------------------------------------
# Describe what our function does
#sub exampleFunction {
#    my $session = shift;
#    print "\tWe're doing some stuff here that you should know about... " unless $quiet;
#    # and here's our code
#    print "DONE!\n" unless $quiet;
#}


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
