#! /usr/bin/perl
use Socket;
use Time::HiRes qw(setitimer ITIMER_REAL);

$name="/tmp/pipo";

sub timerHandler {
	print "ping\n";
}

$SIG{'ALRM'} = 'timerHandler';
setitimer(ITIMER_REAL, 10, 10);

# Create the socket
unlink($name);
socket(Server, PF_UNIX, SOCK_STREAM, 0) || die ("osapd: socket: $!");
bind(Server, sockaddr_un($name)) || die("osapd: bind: $!");
chmod(0777, $name) || die("osapd: chmod $!");
listen(Server, SOMAXCONN) || die("osapd: listen: $!");

while (1) {
	$paddr = accept(Client,Server);
	print("accept returns '$paddr'\n");
}


