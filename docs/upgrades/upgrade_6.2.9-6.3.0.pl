#!/usr/bin/perl

use lib "../../lib";
use FileHandle;
use File::Path;
use Getopt::Long;
use strict;
use WebGUI::Id;
use WebGUI::Page;
use WebGUI::Session;
use WebGUI::SQL;
use WebGUI::URL;


my $configFile;
my $quiet;

GetOptions(
    'configFile=s'=>\$configFile,
	'quiet'=>\$quiet
);

WebGUI::Session::open("../..",$configFile);

print "\tFixing navigation template variables.\n" unless ($quiet);
my $sth = WebGUI::SQL->read("select * from template where namespace in ('Navigation')");
while (my $data = $sth->hashRef) {
        $data->{template} =~ s/page.current/basepage/ig;
        $data->{template} =~ s/isMy/is/ig;
        $data->{template} =~ s/isCurrent/isBasepage/ig;
        $data->{template} =~ s/inCurrentRoot/inBranch/ig;
        WebGUI::SQL->write("update template set template=".quote($data->{template})." where namespace=".quote($data->{namespace})." and templateId=".quote($data->{templateId}));
}
$sth->finish;


print "\tMoving site icons into style templates.\n" unless ($quiet);
my $type = lc($session{setting}{siteicon});
$type =~ s/.*\.(.*?)$/$1/;
my $tags = '	
	<link rel="icon" href="'.$session{setting}{siteicon}.'" type="image/'.$type.'" />
	<link rel="SHORTCUT ICON" href="'.$session{setting}{favicon}.'" />
	<tmpl_var head.tags>
	';
$sth = WebGUI::SQL->read("select templateId,template from template where namespace='style'");
while (my ($id,$template) = $sth->array) {
	$template =~ s/\<tmpl_var head\.tags\>/$tags/ig;
	WebGUI::SQL->write("update template set template=".quote($template)." where templateId=".quote($id)." and namespace='style'");
}
$sth->finish;
WebGUI::SQL->write("delete from settings where name in ('siteicon','favicon')");


print "\tMigrating wobject templates to asset templates.\n" unless ($quiet);
my $sth = WebGUI::SQL->read("select templateId, template, namespace from template where namespace in ('Article', 
		'USS', 'SyndicatedContent', 'MessageBoard', 'DataForm', 'EventsCalendar', 'HttpProxy', 'Poll', 'WobjectProxy',
		'IndexedSearch', 'SQLReport', 'Survey', 'WSClient')");
while (my $t = $sth->hashRef) {
	$t->{template} = '<a name="<tmpl_var assetId>"></a>
<tmpl_if session.var.adminOn>
	<p><tmpl_var controls></p>
</tmpl_if>	
		'.$t->{template};
	WebGUI::SQL->write("update template set template=".quote($t->{template})." where templateId=".quote($t->{templateId})." and namespace=".quote($t->{namespace}));
}
$sth->finish;


# <this is here because we don't want to actually migrate stuff yet
#WebGUI::Session::close();
#exit;
# >this is here because we don't want to actually migrate stuff yet



print "\tConverting Pages, Wobjects, and Forums to Assets\n" unless ($quiet);
print "\t\tHold on cuz this is going to take a long time...\n" unless ($quiet);
print "\t\tMaking first round of table structure changes\n" unless ($quiet);
WebGUI::SQL->write("alter table wobject add column assetId varchar(22) not null");
WebGUI::SQL->write("alter table wobject add styleTemplateId varchar(22) not null");
WebGUI::SQL->write("alter table wobject add printableStyleTemplateId varchar(22) not null");
WebGUI::SQL->write("alter table wobject add cacheTimeout int not null default 60");
WebGUI::SQL->write("alter table wobject add cacheTimeoutVisitor int not null default 3600");
WebGUI::SQL->write("alter table wobject drop primary key");
# next 2 lines are for sitemap to nav migration
WebGUI::SQL->write("alter table Navigation rename tempoldnav");
WebGUI::SQL->write("create table Navigation (assetId varchar(22) not null primary key, assetsToInclude text, startType varchar(35), startPoint varchar(255), endPoint varchar(35), showSystemPages int not null default 0, showHiddenPages int not null default 0, showUnprivilegedPages int not null default 0)");
my $sth = WebGUI::SQL->read("select distinct(namespace) from wobject");
while (my ($namespace) = $sth->array) {
	WebGUI::SQL->write("alter table ".$namespace." add column assetId varchar(22) not null");
}
$sth->finish;
walkTree('0','PBasset000000000000001','000001','1');
print "\t\tMaking second round of table structure changes\n" unless ($quiet);
WebGUI::SQL->write("drop table SiteMap");
WebGUI::SQL->write("delete from template where namespace in ('SiteMap')");
my $sth = WebGUI::SQL->read("select distinct(namespace) from wobject where namespace is not null");
while (my ($namespace) = $sth->array) {
	if (isIn($namespace, qw(Article DataForm EventsCalendar HttpProxy IndexedSearch MessageBoard Poll Product SQLReport Survey SyndicatedContent USS WobjectProxy WSClient))) {
		WebGUI::SQL->write("alter table ".$namespace." drop column wobjectId");
	} else {
		WebGUI::SQL->write("alter table ".$namespace." drop primary key");
	}
	
	WebGUI::SQL->write("alter table ".$namespace." add primary key (assetId)");
}
$sth->finish;
WebGUI::SQL->write("alter table wobject drop column wobjectId");
WebGUI::SQL->write("alter table wobject add primary key (assetId)");
WebGUI::SQL->write("alter table wobject drop column namespace");
WebGUI::SQL->write("alter table wobject drop column pageId");
WebGUI::SQL->write("alter table wobject drop column sequenceNumber");
WebGUI::SQL->write("alter table wobject drop column title");
WebGUI::SQL->write("alter table wobject drop column ownerId");
WebGUI::SQL->write("alter table wobject drop column groupIdEdit");
WebGUI::SQL->write("alter table wobject drop column groupIdView");
WebGUI::SQL->write("alter table wobject drop column userDefined1");
WebGUI::SQL->write("alter table wobject drop column userDefined2");
WebGUI::SQL->write("alter table wobject drop column userDefined3");
WebGUI::SQL->write("alter table wobject drop column userDefined4");
WebGUI::SQL->write("alter table wobject drop column userDefined5");
WebGUI::SQL->write("alter table wobject drop column templatePosition");
WebGUI::SQL->write("alter table wobject drop column bufferUserId");
WebGUI::SQL->write("alter table wobject drop column bufferDate");
WebGUI::SQL->write("alter table wobject drop column bufferPrevId");
WebGUI::SQL->write("alter table wobject drop column forumId");
WebGUI::SQL->write("alter table wobject drop column startDate");
WebGUI::SQL->write("alter table wobject drop column endDate");
WebGUI::SQL->write("alter table wobject drop column addedBy");
WebGUI::SQL->write("alter table wobject drop column dateAdded");
WebGUI::SQL->write("alter table wobject drop column editedBy");
WebGUI::SQL->write("alter table wobject drop column lastEdited");
WebGUI::SQL->write("alter table wobject drop column allowDiscussion");
WebGUI::SQL->write("drop table page");
WebGUI::SQL->write("alter table Article drop column image");
WebGUI::SQL->write("alter table Article drop column attachment");


my %migration;

print "\tConverting navigation system to asset tree\n" unless ($quiet);
my ($navRootLineage) = WebGUI::SQL->quickArray("select assetId,title,lineage from asset where length(lineage)=12 order by lineage desc limit 1");
$navRootLineage = sprintf("%012d",("000001000005"+1));
my $navRootId = WebGUI::SQL->setRow("asset","assetId",{
	assetId=>"new",
	isHidden=>1,
	title=>"Navigation Configurations",
	menuTitle=>"Navigation Configurations",
	url=>fixUrl('doesntexistyet',"Navigation Configurations"),
	ownerUserId=>"3",
	groupIdView=>"4",
	groupIdEdit=>"4",
	parentId=>"PBasset000000000000001",
	lineage=>$navRootLineage,
	lastUpdated=>time(),
	className=>"WebGUI::Admin::Wobject::Navigation",
	state=>"published"
	});
WebGUI::SQL->setRow("wobject","assetId",{
	assetId=>$navRootId,
	templateId=>"1",
	styleTemplateId=>"1",
	printableStyleTemplateId=>"3"
	},undef,$navRootId);
WebGUI::SQL->setRow("Navigation","assetId",{
	assetId=>$navRootId,
	startType=>"relativeToCurrentUrl",
	startPoint=>"0",
	endPoint=>"55",
	assetsToInclude=>"descendants"
	},undef,$navRootId);
my $sth = WebGUI::SQL->read("select * from tempoldnav");
my $navRankCounter = 1;
while (my $data = $sth->hashRef) {
	print "\t\tConverting ".$data->{identifier}."\n" unless ($quiet);
	my (%newNav,%newAsset,%newWobject);
	$newNav{assetId} = $newWobject{assetId} = $newAsset{assetId} = getNewId("nav",$data->{navigationId}); 
	$newAsset{url} = fixUrl($newAsset{assetId},$data->{identifier});
	$newAsset{isHidden} = 1;
	$newAsset{title} = $newAsset{menuTitle} = $data->{identifier};
	$newAsset{ownerUserId} = "3";
	$newAsset{groupIdView} = $newAsset{groupIdEdit} = "4";
	$newAsset{className} = 'WebGUI::Asset::Wobject::Navigation';
	$newAsset{state} = 'published';
	$newAsset{lastUpdated} = time();
	$newAsset{parentId} = $navRootId;
	$newAsset{lineage} = $navRootLineage.sprintf("%06d",$navRankCounter);
	$newWobject{templateId} = $data->{templateId};
	$newWobject{styleTemplateId}="1";
	$newWobject{printableStyleTemplateId}="3";
	$newNav{showSystemPages} = $data->{showSystemPages};
	$newNav{showHiddenPages} = $data->{showHiddenPages};
	$newNav{showUnprivilegedPages} = $data->{showUnprivilegedPages};
	if ($data->{startAt} eq "root") {
		$newNav{startType} = "relativeToRoot";
		$newNav{startPoint} = "0";
	} elsif ($data->{startAt} eq "WebGUIroot") {
		$newNav{startType} = "relativeToRoot";
		$newNav{startPoint} = "1";
	} elsif ($data->{startAt} eq "top") {
		$newNav{startType} = "relativeToRoot";
		$newNav{startPoint} = "2";
	} elsif ($data->{startAt} eq "grandmother") {
		$newNav{startType} = "relativeToCurrentUrl";
		$newNav{startPoint} = "-2";
	} elsif ($data->{startAt} eq "mother") {
		$newNav{startType} = "relativeToCurrentUrl";
		$newNav{startPoint} = "-1";
	} elsif ($data->{startAt} eq "current") {
		$newNav{startType} = "relativeToCurrentUrl";
		$newNav{startPoint} = "0";
	} elsif ($data->{startAt} eq "daughter") {
		$newNav{startType} = "relativeToCurrentUrl";
		$newNav{startPoint} = "1";
	} else {
		$newNav{startType} = "specificUrl";
		$newNav{startPoint} = $data->{startAt};
	}
	$newNav{endPoint} = (($data->{depth} == 99)?55:$data->{depth});
	if ($data->{method} eq "daughters") {
		$newNav{endPoint} = "1";
		$newNav{assetsToInclude} = "descendants";
	} elsif ($data->{method} eq "sisters") {
		$newNav{assetsToInclude} = "siblings";
	} elsif ($data->{method} eq "self_and_sisters") {
		$newNav{assetsToInclude} = "self\nsiblings";
	} elsif ($data->{method} eq "descendants") {
		$newNav{assetsToInclude} = "descendants";
	} elsif ($data->{method} eq "self_and_descendants") {
		$newNav{assetsToInclude} = "self\ndescendants";
	} elsif ($data->{method} eq "leaves_under") {
		$newNav{endPoint} = "1";
		$newNav{assetsToInclude} = "descendants";
	} elsif ($data->{method} eq "generation") {
		$newNav{assetsToInclude} = "self\nsisters";
	} elsif ($data->{method} eq "ancestors") {
		$newNav{endPoint} += $newNav{startPoint} unless ($newNav{startType} eq "specificUrl");
		$newNav{startType} = "relativeToRoot";
		$newNav{startPoint} = $data->{stopAtLevel}+1;
		$newNav{assetsToInclude} = "descendants";
	} elsif ($data->{method} eq "self_and_ancestors") {
		$newNav{endPoint} += $newNav{startPoint} unless ($newNav{startType} eq "specificUrl");
		$newNav{startType} = "relativeToRoot";
		$newNav{startPoint} = $data->{stopAtLevel}+1;
		$newNav{assetsToInclude} = "self\ndescendants";
	} elsif ($data->{method} eq "pedigree") {
		$newNav{endPoint} += $newNav{startPoint} unless ($newNav{startType} eq "specificUrl");
		$newNav{startType} = "relativeToRoot";
		$newNav{startPoint} = $data->{stopAtLevel}+1;
		$newNav{assetsToInclude} = "pedigree";
	}
	WebGUI::SQL->setRow("asset","assetId",\%newAsset,undef,$newNav{assetId});
	WebGUI::SQL->setRow("wobject","assetId",\%newWobject,undef,$newNav{assetId});
	WebGUI::SQL->setRow("Navigation","assetId",\%newNav,undef,$newNav{assetId});
	$navRankCounter++;
}
$sth->finish;
WebGUI::SQL->write("update Navigation set startPoint='root' where startPoint='nameless_root'");
WebGUI::SQL->write("drop table tempoldnav");


print "\tDeleting files which are no longer used.\n" unless ($quiet);
#unlink("../../lib/WebGUI/Page.pm");
#unlink("../../lib/WebGUI/Operation/Page.pm");
#unlink("../../lib/WebGUI/Navigation.pm");
#unlink("../../lib/WebGUI/Operation/Navigation.pm");
#unlink("../../lib/WebGUI/Attachment.pm");
#unlink("../../lib/WebGUI/Node.pm");
#unlink("../../lib/WebGUI/Wobject/Article.pm");
#unlink("../../lib/WebGUI/Wobject/SiteMap.pm");
#unlink("../../lib/WebGUI/Wobject/DataForm.pm");
#unlink("../../lib/WebGUI/Wobject/USS.pm");
#unlink("../../lib/WebGUI/Wobject/FileManager.pm");



WebGUI::Session::close();


sub walkTree {
	my $oldParentId = shift;
	my $newParentId = shift;
	my $parentLineage = shift;
	my $myRank = shift;
	print "\t\tFinding children of page ".$oldParentId."\n" unless ($quiet);
	my $a = WebGUI::SQL->read("select * from page where subroutinePackage='WebGUI::Page' and parentId=".quote($oldParentId)." order by nestedSetLeft");
	while (my $page = $a->hashRef) {
		print "\t\tConverting page ".$page->{pageId}."\n" unless ($quiet);
		my $pageId = WebGUI::Id::generate();
		if ($page->{pageId} eq $session{setting}{defaultPage}) {
			WebGUI::SQL->write("update settings set value=".quote($pageId)." where name='defaultPage'");
		}
		if ($page->{pageId} eq $session{setting}{notFoundPage}) {
			WebGUI::SQL->write("update settings set value=".quote($pageId)." where name='notFoundPage'");
		}
		my $pageLineage = $parentLineage.sprintf("%06d",$myRank);
		my $pageUrl = fixUrl($pageId,$page->{urlizedTitle});
		my $className = 'WebGUI::Asset::Wobject::Layout';
		if ($page->{redirectURL} ne "") {
			$className = 'WebGUI::Asset::Redirect';
		}
		WebGUI::SQL->write("insert into asset (assetId, parentId, lineage, className, state, title, menuTitle, url, startDate, 
			endDate, synopsis, newWindow, isHidden, ownerUserId, groupIdView, groupIdEdit, encryptPage, assetSize ) values (".quote($pageId).",
			".quote($newParentId).", ".quote($pageLineage).", ".quote($className).",'published',".quote($page->{title}).",
			".quote($page->{menuTitle}).", ".quote($pageUrl).", ".quote($page->{startDate}).", ".quote($page->{endDate}).",
			".quote($page->{synopsis}).", ".quote($page->{newWindow}).", ".quote($page->{hideFromNavigation}).", ".quote($page->{ownerId}).",
			".quote($page->{groupIdView}).", ".quote($page->{groupIdEdit}).", ".quote($page->{encryptPage}).",
			".length($page->{title}.$page->{menuTitle}.$page->{synopsis}.$page->{urlizedTitle}).")");
		if ($page->{redirectURL} ne "") {
			WebGUI::SQL->write("insert into redirect (assetId, redirectUrl) values (".quote($pageId).",".quote($page->{redirectURL}).")");
		} else {
			WebGUI::SQL->write("insert into wobject (assetId, styleTemplateId, templateId, printableStyleTemplateId, 
				cacheTimeout, cacheTimeoutVisitor, displayTitle) values (
				".quote($pageId).", ".quote($page->{styleId}).", ".quote($page->{templateId}).", 
				".quote($page->{printableStyleId}).", ".quote($page->{cacheTimeout}).",".quote($page->{cacheTimeoutVisitor}).",
				0)");
			WebGUI::SQL->write("insert into layout (assetId) values (".quote($pageId).")");
		}
		my $rank = 1;
		print "\t\tFinding wobjects on page ".$page->{pageId}."\n" unless ($quiet);
		my $b = WebGUI::SQL->read("select * from wobject where pageId=".quote($page->{pageId})." order by sequenceNumber");
		while (my $wobject = $b->hashRef) {
			print "\t\t\tConverting wobject ".$wobject->{wobjectId}."\n" unless ($quiet);
			my ($namespace) = WebGUI::SQL->quickHashRef("select * from ".$wobject->{namespace}." where wobjectId=".quote($wobject->{wobjectId}));
			my $wobjectId = WebGUI::Id::generate();
			my $wobjectLineage = $pageLineage.sprintf("%06d",$rank);
			my $wobjectUrl = fixUrl($wobjectId,$pageUrl."/".$wobject->{title});
			my $groupIdView = $page->{groupIdView};
			my $groupIdEdit = $page->{groupIdEdit};
			my $ownerId = $page->{ownerId};
			if ($page->{wobjectPrivileges}) {
				$groupIdView = $wobject->{groupIdView};
				$groupIdEdit = $wobject->{groupIdEdit};
				$ownerId = $wobject->{ownerId};
			}
			$className = 'WebGUI::Asset::Wobject::'.$wobject->{namespace};
			WebGUI::SQL->write("insert into asset (assetId, parentId, lineage, className, state, title, menuTitle, url, startDate, 
				endDate, isHidden, ownerUserId, groupIdView, groupIdEdit, encryptPage, assetSize) values (".quote($wobjectId).",
				".quote($pageId).", ".quote($wobjectLineage).", ".quote($className).",'published',".quote($wobject->{title}).",
				".quote($wobject->{title}).", ".quote($wobjectUrl).", ".quote($wobject->{startDate}).", ".quote($wobject->{endDate}).",
				1, ".quote($ownerId).", ".quote($groupIdView).", ".quote($groupIdEdit).", ".quote($page->{encryptPage}).",
				".length($wobject->{title}.$wobject->{description}).")");
			WebGUI::SQL->write("update wobject set assetId=".quote($wobjectId).", styleTemplateId=".quote($page->{styleId}).",
				printableStyleTemplateId=".quote($page->{printableStyleId}).", cacheTimeout=".quote($page->{cacheTimeout})
				.", cacheTimeoutVisitor=".quote($page->{cacheTimeoutVisitor})." where wobjectId=".quote($wobject->{wobjectId}));
			WebGUI::SQL->write("update ".$wobject->{namespace}." set assetId=".quote($wobjectId)." where wobjectId="
				.quote($wobject->{wobjectId}));
			if ($wobject->{namespace} eq "Article") {
				print "\t\t\tMigrating attachments for Article ".$wobject->{wobjectId}."\n" unless ($quiet);
				if ($namespace->{attachment}) {
					my $attachmentId = WebGUI::Id::generate();
					WebGUI::SQL->write("insert into asset (assetId, parentId, lineage, className, state, title, menuTitle, 
						url, startDate, endDate, isHidden, ownerUserId, groupIdView, groupIdEdit) values (".
						quote($attachmentId).", ".quote($wobjectId).", ".quote($wobjectLineage.sprintf("%06d",1)).", 
						'WebGUI::Asset::File','published',".quote($namespace->{attachment}).", ".
						quote($namespace->{attachment}).", ".quote(fixUrl($attachmentId,$wobjectUrl.'/'.$namespace->{attachment})).", 
						".quote($wobject->{startDate}).", ".quote($wobject->{endDate}).", 1, ".quote($ownerId).", 
						".quote($groupIdView).", ".quote($groupIdEdit).")");
					my $storageId = copyFile($namespace->{attachment},$wobject->{wobjectId});
					WebGUI::SQL->write("insert into FileAsset (assetId, filename, storageId, fileSize) values (
						".quote($attachmentId).", ".quote($namespace->{attachment}).", ".quote($storageId).",
						".quote(getFileSize($storageId,$namespace->{attachment})).")");
				}
				if ($namespace->{image}) {
					my $rank = 1;
					$rank ++ if ($namespace->{attachment});
					my $imageId = WebGUI::Id::generate();
					WebGUI::SQL->write("insert into asset (assetId, parentId, lineage, className, state, title, menuTitle, 
						url, startDate, endDate, isHidden, ownerUserId, groupIdView, groupIdEdit) values (".
						quote($imageId).", ".quote($wobjectId).", ".quote($wobjectLineage.sprintf("%06d",$rank)).", 
						'WebGUI::Asset::File::Image','published',".quote($namespace->{image}).", ".
						quote($namespace->{image}).", ".quote(fixUrl($imageId,$wobjectUrl.'/'.$namespace->{image})).", 
						".quote($wobject->{startDate}).", ".quote($wobject->{endDate}).", 1, ".quote($ownerId).", 
						".quote($groupIdView).", ".quote($groupIdEdit).")");
					my $storageId = copyFile($namespace->{image},$wobject->{wobjectId});
					copyFile('thumb-'.$namespace->{image},$wobject->{wobjectId},$storageId);
					WebGUI::SQL->write("insert into FileAsset (assetId, filename, storageId, fileSize) values (
						".quote($imageId).", ".quote($namespace->{image}).", ".quote($storageId).",
						".quote(getFileSize($storageId,$namespace->{image})).")");
					WebGUI::SQL->write("insert into ImageAsset (assetId, thumbnailSize) values (".quote($imageId).",
						".quote($session{setting}{thumbnailSize}).")");
				}
				# migrate forums
				rmtree($session{config}{uploadsPath}.'/'.$wobject->{wobjectId});
			} elsif ($wobject->{namespace} eq "SiteMap") {
				print "\t\t\tConverting SiteMap ".$wobject->{wobjectId}." into Navigation\n" unless ($quiet);
				my ($starturl) = WebGUI::SQL->quickArray("select urlizedTitle from page 
					where pageId=".quote($namespace->{startAtThisLevel}));
				WebGUI::SQL->setRow("Navigation","assetId",{
					assetId=>$wobjectId,
					endPoint=>$namespace->{depth},
					startPoint=>$starturl,
					startType=>"specificUrl",
					assetsToInclude=>"descendants"
					},undef,$wobjectId);
				WebGUI::SQL->write("update asset set className='WebGUI::Asset::Wobject::Navigation' where assetId=".quote($wobjectId));
				WebGUI::SQL->write("update wobject set namespace='Navigation', templateId='1' where assetId=".quote($wobjectId));
			} elsif ($wobject->{namespace} eq "FileManager") {
				print "\t\t\tConverting File Manager ".$wobject->{wobjectId}." into File Folder Layout\n" unless ($quiet);
				WebGUI::SQL->write("update asset set className='WebGUI::Asset::Layout' where assetId=".quote($wobjectId));
				WebGUI::SQL->write("insert into layout (assetId) values (".quote($wobjectId).")");
				WebGUI::SQL->write("update wobject set templateId='15' where wobjectId=".quote($wobjectId));
				print "\t\t\tMigrating attachments for File Manager ".$wobject->{wobjectId}."\n" unless ($quiet);
				my $sth = WebGUI::SQL->read("select * from FileManager_file where wobjectId=".quote($wobjectId)." order by sequenceNumber");
				my $rank = 1;
				while (my $data = $sth->hashRef) {
					foreach my $field ("downloadFile","alternateVersion1","alternateVersion2") {
						next if ($data->{$field} eq "");
						print "\t\t\t\tMigrating file ".$data->{$field}." (".$data->{FileManager_fileId}.")\n" unless ($quiet);
						my $newId = WebGUI::Id::generate();
						my $storageId = copyFile($data->{$field},$wobject->{wobjectId}.'/'.$data->{FileManager_fileId});
						my $class;
						if (isIn(getFileExtension($data->{$field}), qw(jpg jpeg gif png))) {
							copyFile('thumb-'.$data->{$field},$wobject->{wobjectId}.'/'.$data->{FileManager_fileId},$storageId);
							WebGUI::SQL->write("insert into ImageAsset (assetId, thumbnailSize) values (".quote($newId).",
								".quote($session{setting}{thumbnailSize}).")");
							$class = 'WebGUI::Asset::File::Image';
						} else {
							$class = 'WebGUI::Asset::File';
						}
						WebGUI::SQL->write("insert into FileAsset (assetId, filename, storageId, fileSize) values (
							".quote($newId).", ".quote($data->{$field}).", ".quote($storageId).",
							".quote(getFileSize($storageId,$data->{$field})).")");
						WebGUI::SQL->write("insert into asset (assetId, parentId, lineage, className, state, title, menuTitle, 
							url, startDate, endDate, isHidden, ownerUserId, groupIdView, groupIdEdit, synopsis) values (".
							quote($newId).", ".quote($wobjectId).", ".quote($wobjectLineage.sprintf("%06d",1)).", 
							'".$class."','published',".quote($data->{fileTitle}).", ".
							quote($data->{fileTitle}).", ".quote(fixUrl($newId,$wobjectUrl.'/'.$data->{$field})).", 
							".quote($wobject->{startDate}).", ".quote($wobject->{endDate}).", 1, ".quote($ownerId).", 
							".quote($data->{groupToView}).", ".quote($groupIdEdit).", ".quote($data->{briefSynopsis}).")");
						$rank++;
					}
				}
				$sth->finish;
				rmtree($session{config}{uploadsPath}.'/'.$wobject->{wobjectId});
			} elsif ($wobject->{namespace} eq "Product") {
				# migrate attachments to file assets
				# migrate images to image assets
			} elsif ($wobject->{namespace} eq "USS") {
				# migrate master forum
				# migrate submissions
				# migrate submission forums
				# migrate submission attachments
				# migrate submission images
			} elsif ($wobject->{namespace} eq "MessageBoard") {
				# migrate forums
			}
			$rank++;
		}
		$b->finish;
		if ($className eq "WebGUI::Asset::Wobject::Layout") { # Let's position some content
			my $positions;
			my $last = 1;
			my @assets;
			my @positions;
			my $b = WebGUI::SQL->read("select assetId, templatePosition from wobject where pageId=".quote($page->{pageId})."
				order by templatePosition, sequenceNumber");
			while (my ($assetId, $position) = $b->array) {
				if ($position ne $last) {
					push(@positions,join(",",@assets));
					@assets = ();
				}
				$last = $position;
				push(@assets,$assetId);
			}
			$b->finish;
			my $contentPositions = join("\.",@positions);
			WebGUI::SQL->write("update layout set contentPositions=".quote($contentPositions)." where assetId=".quote($pageId));
		}
		walkTree($page->{pageId},$pageId,$pageLineage,$rank);
		$myRank++;
	}
	$a->finish;
}




sub fixUrl {
	my $id = shift;
        my $url = shift;
        $url = WebGUI::URL::urlize($url);
        my ($test) = WebGUI::SQL->quickArray("select url from asset where assetId<>".quote($id)." and url=".quote($url));
        if ($test) {
                my @parts = split(/\./,$url);
                if ($parts[0] =~ /(.*)(\d+$)/) {
                        $parts[0] = $1.($2+1);
                } elsif ($test ne "") {
                        $parts[0] .= "2";
                }
                $url = join(".",@parts);
                $url = fixUrl($url);
        }
        return $url;
}

sub copyFile {
	my $filename = shift;
	my $oldPath = shift;
	my $id = shift || WebGUI::Id::generate();
	$id =~ m/^(.{2})(.{2})/;
	my $node = $session{config}{uploadsPath}.$session{os}{slash}.$1;
	mkdir($node);
	$node .= $session{os}{slash}.$2;
	mkdir($node);
	$node .= $session{os}{slash}.$id;
	mkdir($node);
	my $a = FileHandle->new($session{config}{uploadPath}.$session{os}{slash}.$oldPath.$session{os}{slash}.$filename,"r");
        binmode($a);
        my $b = FileHandle->new(">".$node.$session{os}{slash}.$filename);
        binmode($b);
        cp($a,$b);
	return $id;
}

sub getFileSize {
	my $id = shift;
	my $filename = shift;
	$id =~ m/^(.{2})(.{2})/;
	my $path = $session{config}{uploadsPath}.$session{os}{slash}.$1.$session{os}{slash}.$2.$session{os}{slash}.$id.$session{os}{slash}.$filename;
	my (@attributes) = stat($path);
	return $attributes[7];
}

sub getFileExtension {
	my $filename = shift;
        my $extension = lc($filename);
        $extension =~ s/.*\.(.*?)$/$1/;
        return $extension;
}

sub isIn {
        my $key = shift;
        $_ eq $key and return 1 for @_;
        return 0;
}


sub getNewId {
	my $type = shift;
	my $oldId = shift;
	my $namespace = shift;
	my $migration = {'tmpl' => {
                      'Operation/MessageLog/View' => {
                                                       '1' => 'PBtmpl0000000000000050'
                                                     },
                      'Forum/Search' => {
                                          '1' => 'PBtmpl0000000000000031'
                                        },
                      'Auth/WebGUI/Account' => {
                                                 '1' => 'PBtmpl0000000000000010'
                                               },
                      'Forum/PostPreview' => {
                                               '1' => 'PBtmpl0000000000000030'
                                             },
                      'MessageBoard' => {
                                          '1' => 'PBtmpl0000000000000047'
                                        },
                      'FileManager' => {
                                         '1' => 'PBtmpl0000000000000025',
                                         '2' => 'PBtmpl0000000000000087'
                                       },
                      'Operation/Profile/View' => {
                                                    '1' => 'PBtmpl0000000000000052'
                                                  },
                      'Forum/PostForm' => {
                                            '1' => 'PBtmpl0000000000000029'
                                          },
                      'Operation/RedeemSubscription' => {
                                                          '1' => 'PBtmpl0000000000000053'
                                                        },
                      'Navigation' => {
                                        '8' => 'PBtmpl0000000000000136',
                                        '6' => 'PBtmpl0000000000000130',
                                        '1001' => 'PBtmpl0000000000000075',
                                        '4' => 'PBtmpl0000000000000117',
                                        '1' => 'PBtmpl0000000000000048',
                                        '3' => 'PBtmpl0000000000000108',
                                        '7' => 'PBtmpl0000000000000134',
                                        '1000' => 'PBtmpl0000000000000071',
                                        '2' => 'PBtmpl0000000000000093',
                                        '5' => 'PBtmpl0000000000000124'
                                      },
                      'Macro/L_loginBox' => {
                                              '1' => 'PBtmpl0000000000000044',
                                              '2' => 'PBtmpl0000000000000092'
                                            },
                      'Commerce/ConfirmCheckout' => {
                                                      '1' => 'PBtmpl0000000000000016'
                                                    },
                      'prompt' => {
                                    '1' => 'PBtmpl0000000000000057'
                                  },
                      'Auth/SMB/Login' => {
                                            '1' => 'PBtmpl0000000000000009'
                                          },
                      'ImageAsset' => {
                                        '2' => 'PBtmpl0000000000000088'
                                      },
                      'AttachmentBox' => {
                                           '1' => 'PBtmpl0000000000000003'
                                         },
                      'Forum' => {
                                   '1' => 'PBtmpl0000000000000026'
                                 },
                      'Poll' => {
                                  '1' => 'PBtmpl0000000000000055'
                                },
                      'FileAsset' => {
                                       '1' => 'PBtmpl0000000000000024'
                                     },
                      'HttpProxy' => {
                                       '1' => 'PBtmpl0000000000000033'
                                     },
                      'Auth/SMB/Create' => {
                                             '1' => 'PBtmpl0000000000000008'
                                           },
                      'Commerce/ViewPurchaseHistory' => {
                                                          '1' => 'PBtmpl0000000000000019'
                                                        },
                      'Article' => {
                                     '6' => 'PBtmpl0000000000000129',
                                     '4' => 'PBtmpl0000000000000115',
                                     '1' => 'PBtmpl0000000000000002',
                                     '3' => 'PBtmpl0000000000000103',
                                     '2' => 'PBtmpl0000000000000084',
                                     '5' => 'PBtmpl0000000000000123'
                                   },
                      'style' => {
                                   '6' => 'PBtmpl0000000000000132',
                                   'adminConsole' => 'PBtmpl0000000000000137',
                                   '3' => 'PBtmpl0000000000000111',
                                   '1001' => 'PBtmpl0000000000000076',
                                   '1' => 'PBtmpl0000000000000060',
                                   '1000' => 'PBtmpl0000000000000072',
                                   '10' => 'PBtmpl0000000000000070'
                                 },
                      'Macro/SubscriptionItem' => {
                                                    '1' => 'PBtmpl0000000000000046'
                                                  },
                      'WSClient' => {
                                      '1' => 'PBtmpl0000000000000069',
                                      '2' => 'PBtmpl0000000000000100'
                                    },
                      'Operation/MessageLog/Message' => {
                                                          '1' => 'PBtmpl0000000000000049'
                                                        },
                      'Auth/SMB/Account' => {
                                              '1' => 'PBtmpl0000000000000007'
                                            },
                      'Survey' => {
                                    '1' => 'PBtmpl0000000000000061'
                                  },
                      'EventsCalendar' => {
                                            '1' => 'PBtmpl0000000000000022',
                                            '3' => 'PBtmpl0000000000000105',
                                            '2' => 'PBtmpl0000000000000086'
                                          },
                      'Macro/AdminToggle' => {
                                               '1' => 'PBtmpl0000000000000036'
                                             },
                      'Auth/LDAP/Create' => {
                                              '1' => 'PBtmpl0000000000000005'
                                            },
                      'Auth/WebGUI/Create' => {
                                                '1' => 'PBtmpl0000000000000011'
                                              },
                      'page' => {
                                  '6' => 'PBtmpl0000000000000131',
                                  '3' => 'PBtmpl0000000000000109',
                                  '7' => 'PBtmpl0000000000000135',
                                  '2' => 'PBtmpl0000000000000094',
                                  '15' => 'PBtmpl0000000000000078',
                                  '1' => 'PBtmpl0000000000000054',
                                  '4' => 'PBtmpl0000000000000118',
                                  '5' => 'PBtmpl0000000000000125'
                                },
                      'Macro/H_homeLink' => {
                                              '1' => 'PBtmpl0000000000000042'
                                            },
                      'USS' => {
                                 '6' => 'PBtmpl0000000000000133',
                                 '21' => 'PBtmpl0000000000000102',
                                 '3' => 'PBtmpl0000000000000112',
                                 '2' => 'PBtmpl0000000000000097',
                                 '17' => 'PBtmpl0000000000000081',
                                 '20' => 'PBtmpl0000000000000101',
                                 '15' => 'PBtmpl0000000000000079',
                                 '14' => 'PBtmpl0000000000000077',
                                 '4' => 'PBtmpl0000000000000121',
                                 '1' => 'PBtmpl0000000000000066',
                                 '18' => 'PBtmpl0000000000000082',
                                 '1000' => 'PBtmpl0000000000000074',
                                 '16' => 'PBtmpl0000000000000080',
                                 '19' => 'PBtmpl0000000000000083',
                                 '5' => 'PBtmpl0000000000000128'
                               },
                      'AdminConsole' => {
                                          '1' => 'PBtmpl0000000000000001'
                                        },
                      'SQLReport' => {
                                       '1' => 'PBtmpl0000000000000059'
                                     },
                      'Macro/AdminBar' => {
                                            '1' => 'PBtmpl0000000000000035',
                                            '2' => 'PBtmpl0000000000000090'
                                          },
                      'Survey/Gradebook' => {
                                              '1' => 'PBtmpl0000000000000062'
                                            },
                      'DataForm/List' => {
                                           '1' => 'PBtmpl0000000000000021'
                                         },
                      'Macro/GroupDelete' => {
                                               '1' => 'PBtmpl0000000000000041'
                                             },
                      'Product' => {
                                     '4' => 'PBtmpl0000000000000119',
                                     '1' => 'PBtmpl0000000000000056',
                                     '3' => 'PBtmpl0000000000000110',
                                     '2' => 'PBtmpl0000000000000095'
                                   },
                      'Commerce/TransactionError' => {
                                                       '1' => 'PBtmpl0000000000000018'
                                                     },
                      'IndexedSearch' => {
                                           '1' => 'PBtmpl0000000000000034',
                                           '3' => 'PBtmpl0000000000000106',
                                           '2' => 'PBtmpl0000000000000089'
                                         },
                      'Auth/WebGUI/Expired' => {
                                                 '1' => 'PBtmpl0000000000000012'
                                               },
                      'Commerce/SelectPaymentGateway' => {
                                                           '1' => 'PBtmpl0000000000000017'
                                                         },
                      'Macro/File' => {
                                        '1' => 'PBtmpl0000000000000039',
                                        '3' => 'PBtmpl0000000000000107',
                                        '2' => 'PBtmpl0000000000000091'
                                      },
                      'Survey/Overview' => {
                                             '1' => 'PBtmpl0000000000000063'
                                           },
                      'Macro/a_account' => {
                                             '1' => 'PBtmpl0000000000000037'
                                           },
                      'Macro/LoginToggle' => {
                                               '1' => 'PBtmpl0000000000000043'
                                             },
                      'Auth/LDAP/Account' => {
                                               '1' => 'PBtmpl0000000000000004'
                                             },
                      'Survey/Response' => {
                                             '1' => 'PBtmpl0000000000000064'
                                           },
                      'Commerce/CheckoutCanceled' => {
                                                       '1' => 'PBtmpl0000000000000015'
                                                     },
                      'USS/Submission' => {
                                            '1' => 'PBtmpl0000000000000067',
                                            '3' => 'PBtmpl0000000000000113',
                                            '2' => 'PBtmpl0000000000000098'
                                          },
                      'Auth/WebGUI/Recovery' => {
                                                  '1' => 'PBtmpl0000000000000014'
                                                },
                      'Macro/r_printable' => {
                                               '1' => 'PBtmpl0000000000000045'
                                             },
                      'Operation/Profile/Edit' => {
                                                    '1' => 'PBtmpl0000000000000051'
                                                  },
                      'SyndicatedContent' => {
                                               '1' => 'PBtmpl0000000000000065',
                                               '1000' => 'PBtmpl0000000000000073'
                                             },
                      'USS/SubmissionForm' => {
                                                '4' => 'PBtmpl0000000000000122',
                                                '1' => 'PBtmpl0000000000000068',
                                                '3' => 'PBtmpl0000000000000114',
                                                '2' => 'PBtmpl0000000000000099'
                                              },
                      'EventsCalendar/Event' => {
                                                  '1' => 'PBtmpl0000000000000023'
                                                },
                      'Macro/GroupAdd' => {
                                            '1' => 'PBtmpl0000000000000040'
                                          },
                      'Forum/Notification' => {
                                                '1' => 'PBtmpl0000000000000027'
                                              },
                      'Auth/LDAP/Login' => {
                                             '1' => 'PBtmpl0000000000000006'
                                           },
                      'DataForm' => {
                                      '4' => 'PBtmpl0000000000000116',
                                      '1' => 'PBtmpl0000000000000020',
                                      '3' => 'PBtmpl0000000000000104',
                                      '2' => 'PBtmpl0000000000000085'
                                    },
                      'Auth/WebGUI/Login' => {
                                               '1' => 'PBtmpl0000000000000013'
                                             },
                      'richEditor' => {
                                        'tinymce' => 'PBtmpl0000000000000138',
                                        '5' => 'PBtmpl0000000000000126'
                                      },
                      'Forum/Thread' => {
                                          '1' => 'PBtmpl0000000000000032'
                                        },
                      'Forum/Post' => {
                                        '1' => 'PBtmpl0000000000000028'
                                      },
                      'Macro/EditableToggle' => {
                                                  '1' => 'PBtmpl0000000000000038'
                                                },
                      'richEditor/pagetree' => {
                                                 '1' => 'PBtmpl0000000000000058'
                                               }
                    },
          'nav' => {
                     '1002' => 'PBnav00000000000000005',
                     '11' => 'PBnav00000000000000006',
                     '7' => 'PBnav00000000000000019',
                     '2' => 'PBnav00000000000000014',
                     '17' => 'PBnav00000000000000012',
                     '1' => 'PBnav00000000000000001',
                     '18' => 'PBnav00000000000000013',
                     '16' => 'PBnav00000000000000011',
                     '13' => 'PBnav00000000000000008',
                     'iBkcoHUb-z4vzYPyX0oS5A' => 'PBnav00000000000000023',
                     '6' => 'PBnav00000000000000018',
                     'b3XBaWXeMXS39HPDfV2y5Q' => 'PBnav00000000000000022',
                     '3' => 'PBnav00000000000000015',
                     '9' => 'PBnav00000000000000021',
                     '12' => 'PBnav00000000000000007',
                     '14' => 'PBnav00000000000000009',
                     '15' => 'PBnav00000000000000010',
                     '8' => 'PBnav00000000000000020',
                     '1001' => 'PBnav00000000000000004',
                     '4' => 'PBnav00000000000000016',
                     '1000' => 'PBnav00000000000000003',
                     '10' => 'PBnav00000000000000002',
                     '5' => 'PBnav00000000000000017'
                   }
        };
	my $newId;
	if ($type eq "nav") {
		$newId = $migration->{nav}{$oldId};
	} elsif ($type eq "tmpl") {
		$newId = $migration->{tmpl}{$namespace}{$oldId};
	}
	$newId = WebGUI::Id::generate() unless ($newId);
	return $newId;
}
