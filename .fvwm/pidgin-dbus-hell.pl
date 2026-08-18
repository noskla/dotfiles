#!/usr/bin/env perl
# if i error install this: https://packages.debian.org/sid/libnet-dbus-perl
use strict; use warnings;

use Getopt::Long;
use Net::DBus;

# usage:
# -s or --server  - server hostname or ip (required)
# -n or --nick    - nickname (required)
# -w or --password - password (optional, default anonymous auth)
# -p or --port    = server port, default to 6667 ot 6697 if -e true
# -e or --encrypted - if to use ssl/tls (ircs)

my ($server, $nick, $password, $port, $encrypted);

GetOptions(  # parse cli args
	's|server=s'=>\$server,
	'n|nick=s'=>\$nick,
	'w|password=s'=>\$password,
	'p|port=i'=>\$port,
	'e|encrypted'=>\$encrypted
);

if (!$server || !$nick) {
	print "missing args\n";
	exit(1);
}

$port ||= ($encrypted ? 6697 : 6667);
my $username = "${nick}\@${server}";
my $protocol = "prpl-irc";
my ($bus, $purple);


# D:
eval {
	$bus = Net::DBus->session();
	my $service = $bus->get_service("im.pidgin.purple.PurpleService");
	$purple = $service->get_object("/im/pidgin/purple/PurpleObject",
		"im.pidgin.purple.PurpleInterface");
};

# if $purple is nuke it means pidgin is down, start it and try again
if ($@) {
	system("pidgin &");
	sleep(3); #give pidgin a second, or two, or three to start
	

	eval {
		$bus = Net::DBus->session();
		my $service = $bus->get_service("im.pidgin.purple.PurpleService");
		$purple = $service->get_object("/im/pidgin/purple/PurpleObject",
		"im.pidgin.purple.PurpleInterface");
	};


	if ($@) {
		die "pidgin dbus is kill$@\n";
	}
}

my $account = $purple->PurpleAccountsFind($username, $protocol);

if (!$account || $account == 0) { # handle case where acconut doesnt exist
	$account = $purple->PurpleAccountNew($username, $protocol);
	$purple->PurpleAccountsAdd($account);

	if (defined $password && $password ne '') {
		$purple->PurpleAccountSetPassword($account, $password);
	}

	$purple->PurpleAccountSetInt($account, "port", $port);
	$purple->PurpleAccountSetBool($account, "ssl", $encrypted ? 1 : 0);
}

# connect
my $ui = $purple->PurpleCoreGetUi();
$purple->PurpleAccountSetEnabled($account, $ui, 1);
$purple->PurpleAccountConnect($account);

print "ok\n";

