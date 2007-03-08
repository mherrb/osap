#! /usr/bin/perl

$cmd = "pfctl -tleased -Ts";
if (!open PFCTL, "$cmd|") {
	syslog(LOG_ERR, "pfctl: $!");
	return;
}
$i=0;
while (<PFCTL>) {
	my $l = $_;
	$l =~  s/^ +//;
	chomp $l;
	print "-> $l\n";
	$leases[$i++] = $l;
}	
close PFCTL;
for ($i = 0; $i <= $#leases; $i++) {
	printf("leases[%d]: %s\n", $i, $leases[$i]);
}
