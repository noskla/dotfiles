#!/usr/bin/env perl
use strict;
use warnings;
use JSON::PP;

my $home_dir = (getpwuid $<)[7] || $ENV{HOME} || '';
die "impossible to find user home directory\n" unless $home_dir;
my $sess_list_json = "$home_dir/.fvwm/ssh_sessions.json";

if (open my $fh, '<', $sess_list_json) {
	local $/;
	my $json_txt = <$fh>;
	close $fh;

	my $sessions = decode_json($json_txt);
	while (my ($name, $data) = each %$sessions) {
		my ($host, $user, $port, $key, $pass);

		if (ref($data) eq 'HASH') {
			$host = $data->{host} || '';
			$user = $data->{user};
			$port = $data->{port};
			$key = $data->{identity_file};
			$pass = $data->{password};
		} else {
			$host = $data;
		}

		next unless $host;

		my $cmd = '';

		# If ssh session requires password authenetication
		if (defined $pass && $pass ne '') {
			my $e_pass = $pass;
			$e_pass =~ s/'/'\\''/g;
			$cmd .= "sshpass -p '$e_pass' ";
		}

		$cmd .= "ssh ";

		if (defined $key && $key ne '') {
			$cmd .= "-i $key ";
		}

		# If non-default ssh port
		if (defined $port && $port ne '') {
			$cmd .= "-p $port ";
		}

		my $target = defined $user && $user ne '' ? "$user\@$host" : $host;
		$cmd .= " $target";

		print qq(AddToMenu SSHSessions "$name" Exec xterm -e $cmd\n);
	}
	print qq(AddToMenu SSHSessions "" Nop\n);
	print qq(AddToMenu SSHSessions "Add new" Exec exec perl ~/.fvwm/add_to_sess_json.pl &\n);
} else {
	print qq(+ "error loading session json" Nop\n);
}

