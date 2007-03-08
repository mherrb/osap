#!/usr/bin/perl --  # -*-Perl-*-
use Socket;
use IO::Handle;
use Sys::Syslog qw(:standard :extended);
use DB_File;
use Time::HiRes qw(setitimer ITIMER_REAL);

#----------------------------------------------------------------------
# Configuration
#
$name='/tmp/osap.socket';
$table='osap_users';
$db='/var/db/osap.db';
$log_facility=LOG_DAEMON;

#----------------------------------------------------------------------
# Handler of cleanup timer - just mark that cleanup is needed
#
sub timerHandler {
	$do_clean++;
}

#----------------------------------------------------------------------
# Get the 'leased' table from pf
#
sub get_leases {
	my %leases;

	$cmd = "pfctl -tleased -Ts";
	if (!open PFCTL, "$cmd|") {
		syslog(LOG_ERR, "pfctl: $!");
		return;
	}
	my $i=0;
	while (<PFCTL>) {
		my $l = $_;
		$l =~  s/^ +//;
		chomp $l;
		$leases{$l} = 1;
	}
	close PFCTL;
	return %leases;
}

#----------------------------------------------------------------------
# Clean db
#
sub clean_db {
	my %leases = get_leases;
	
	foreach $a (keys %osapdb) {
		# Remove addresses that are not in leased table
		if (!$leases{$a}) {
			syslog(LOG_INFO, "clean_db: removing $a");
			my $cmd = "pfctl -q -t $table -T delete $a";
			system($cmd);
			delete($osapdb{$a});
		}
	}
	# mark done
	$do_clean = 0;
}

#----------------------------------------------------------------------
#
# Main code
#

# Init syslog
setlogsock('unix');
openlog('osapd', "ndelay,pid", $log_facility);

# Create the socket
unlink($name);
socket(Server, PF_UNIX, SOCK_STREAM, 0) || die ("osapd: socket: $!");
bind(Server, sockaddr_un($name)) || die("osapd: bind: $!");
chmod(0777, $name) || die("osapd: chmod $!");
listen(Server, SOMAXCONN) || die("osapd: listen: $!");

# open DB
$db = tie(%osapdb, 'DB_File', $db, O_CREAT|O_RDWR, 0600, $DB_HASH) 
  || die("osapd: tie: $!");

# restore pf table
foreach $ip (keys %osapdb) {
	my $user = $osapdb{$ip};
	my $cmd = "pfctl -q -t $table -T add $ip";
	my $result = `$cmd 2>&1`;
	if ($result ne '') {
		syslog(LOG_ERR, "adding $ip");
	}
	syslog(LOG_INFO, "restoring '$ip' '$user'");
}

# timer
$SIG{ALRM} = 'timerHandler';
setitimer(ITIMER_REAL, 60, 60);

syslog(LOG_DEBUG, "Waiting for connection");
while (1) {
	do {
		$paddr = accept(Client,Server);
		clean_db if ($do_clean);
	} until defined(Client);
	Client->autoflush(1);
	while (defined($line = <Client>)) {
    		chop $line;
    		syslog(LOG_DEBUG, "got '$line'");
    		$cmd = '';
    		if ($line =~ /^ADD (.*) (.*)/i) {
      			$cmd = "pfctl -q -t $table -T add $1";
			$osapdb{$1} = $2; # $user
    		} elsif ($line =~ /^DEL (.*)/i) {
      			$cmd = "pfctl -q -t $table -T delete $1";
			delete($osapdb{$1});
    		} elsif ($line =~ /^TST (.*)/i) {
      			# $cmd = "pfctl -q -t $table -T test $1";
			$result = $osapdb{$1};
			syslog(LOG_INFO, "test '$1' -> $result");
			print Client "$result\n";
    		} elsif (uc($line) eq "QUIT") {
      			last;
    		} else {
      			print Client "unrecognized command '$line'\n";
    		}
	
    		if ($cmd ne '') {
			syslog(LOG_INFO, "executing $cmd");
			my $result = `$cmd 2>&1`;
			if ($result ne '') {
				print Client $result;
			} else {
				print Client "OK\n";
    			}
		}
	} # while
	$db->sync;
	syslog(LOG_DEBUG, "Done with one client\n");
	close(Client);
}
print "for loop exited\n";
untie $osapdb;

