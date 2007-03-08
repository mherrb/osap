#! /usr/bin/perl -w
use Net::LDAP;

sub ldap_check_passwd {
	($login, $passwd) = @_;

	my $ldap = Net::LDAP->new('ldaps://ldap.laas.fr') || die "ldap: $@";
	my $mesg = $ldap->bind;
	
	if ($mesg->code) {
		print STDERR "ldap anon bind error";
		return 0;
	}
	print "checking $login...\n";
	$mesg = $ldap->search(base=>'dc=laas,dc=fr', filter=>"(uid=$login)");
	if ($mesg->code || $mesg->count != 1) {
		print STDERR "ldap search error".$mesg->code.$mesg->count."\n";
		$ldap->unbind;
		return 0;
	}
	my $dn = $mesg->entry(0)->dn;

	$mesg = $ldap->bind("$dn", password=>"$passwd");
	if ($mesg->code) {
		print STDERR "ldap bind error";
		$ldap->unbind;	
		return 0;
	} 
	$ldap->unbind;
	return 1;
}

print "Login: ";
chomp($login = <STDIN>);
system "stty -echo";
print "Password: ";
chomp($passwd = <STDIN>);
print "\n";
system "stty echo";

if (ldap_check_passwd($login, $passwd)) {
	print "OK\n";
} else {
	print "not OK\n";
}
