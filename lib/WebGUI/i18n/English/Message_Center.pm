package WebGUI::i18n::English::Message_Center;

use strict;

our $I18N = {

	'receive inbox emails' => {
		message => q|Receive Inbox message notifications via email?|,
		context => q|Allows a user to choose how they get notified about things in their Inbox.|,
		lastUpdated => 1235685248,
	},

	'receive inbox sms' => {
		message => q|Receive Inbox message notifications via SMS?|,
		context => q|Allows a user to choose how they get notified about things in their Inbox.|,
		lastUpdated => 1235685248,
	},

	'sms gateway' => {
		message => q|SMS gateway|,
		context => q|email to SMS/text email address for this site.|,
		lastUpdated => 1235685248,
	},

	'sms gateway help' => {
		message => q|The email address that this site would use to send an SMS message.|,
		lastUpdated => 1235695517,
	},

	'send inbox notifications only' => {
		message => q|Send only Inbox notifications|,
		context => q|Site setting.  A notification is a short message that something is in the Inbox.|,
		lastUpdated => 1235685248,
	},

	'send inbox notifications only help' => {
		message => q|Should WebGUI just send notifications about Inbox messages, instead of the message itself?|,
		lastUpdated => 1235696295,
	},

	'inbox notification' => {
		message => q|You have a new message in your Inbox.|,
		lastUpdated => 1235708853,
	},

};

1;
#vim:ft=perl
