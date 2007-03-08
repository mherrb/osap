#!/usr/bin/perl --  # -*-Perl-*-
use CGI;
use CGI::Pretty qw(:html3);
use Socket;
use IO::Handle;
use Net::LDAP;
use Sys::Syslog qw(:standard :extended);

#----------------------------------------------------------------------
# Configuration section
#
$sockname =   '/tmp/osap.socket';	# name of Unix socket of osapd.pl
$ldapserver = 'ldaps://ldap.laas.fr';	# LDAP server name or URL
$ldapbasedn = 'dc=laas,dc=fr';		# LDAP base DN
 
#----------------------------------------------------------------------
#
# Create the main login window
#
sub login_window
{
	my $q = @_[0];
	
	print $q->header, $q->start_html(-title=>'OSAP Login',
					 -style=>{-src=>'/osap/osap.css'});
	
	print $q->h1('Open Secure Access Point');
	print $q->start_form;
	print $q->start_table({-width=>'100%'},{-border=>'0'});
	my $login_widget=$q->table($q->Tr($q->td({-align=>RIGHT}, 'Login:'),
					  $q->td($q->textfield({-size=>8, 
								name=>'login'}))),
				   $q->Tr($q->td({-align=>RIGHT}, 'Password:'),
					  $q->td($q->password_field({-size=>8, 
								     name=>'passwd'}))),
				   $q->Tr($q->td({-colspan=>2, align=>RIGHT},
						 $q->submit({-name=>OK, -value=>OK, 
							     -class=>oswap-button-ok}))));
	
	print $q->Tr($q->td($q->img({src=>'/osap/puf200X172.gif', 
				     width=>'200', 
				     height=>'172'})),
		     $q->td($login_widget));
	my $read_terms="I've read and accepted the ";
	my $terms_link=$q->a({-href=>'/osap/terms.html'}, 'terms of service');
	print "\n";
	print $q->Tr($q->td({-colspan=>2, align=>CENTER},
			    $q->checkbox({-name=>'terms', 
					  -class=>'oswap-checkbox',
					  -label=>$read_terms}),
			    $terms_link));
	# print $read_terms . $terms_link;
	print $q->end_table, "\n";
	print $q->end_form, "\n";
	my $openbsd = $q->a({-href=>'http://www.openbsd.org/'}, 'OpenBSD');
	print $q->div({-align=>RIGHT}, "powered by $openbsd"), "\n";
}

#----------------------------------------------------------------------
# 
# Create the 'session' window, displayed while the connection is active
#
sub session_window {
	my $q = $_[0];
	my $ip = $q->remote_addr;
	my $login = $q->param('login');
	
	print $q->header, $q->start_html(-title=>'OSAP Session',
					 -style=>{-src=>'/osap/osap.css'});
	print $q->h1("Welcome on the network, $login");
	print $q->start_form;
	print $q->h2({align=>CENTER}, "Please keep this window open.");
	print $q->p("&nbsp;Once you want to disconnect from the network, ",
	    "click on the button below:");
	print $q->p("You can add this page to your bookmarks to come ",
		   "back here later.");
	print $q->start_table({width=>'100%'});
	print $q->Tr({align=>CENTER},
		     $q->td($q->submit({-name=>'Disconnect',
					-class=>'oswap-button-cancel'})));
	print $q->end_table;
	print $q->end_form;
}

#----------------------------------------------------------------------
#
# Create the 'disconnected' screen.
#
sub disconnected_window {
	my $q = $_[0];
	my $myself = $q->self_url;
	
	print $q->header, $q->start_html(-title=>'OSAP Disconnected',
					 -style=>{-src=>'/osap/osap.css'});
	print $q->h1("Disconnected.");
	print $q->p("Thank you for using the OSAP service.");
	print $q->p("You are now disconnected from the network.");
	print $q->p("Click ", $q->a({href=>"$myself"}, 'here'), 
		    " to reconnect");
	print $q->p("Good bye.");
}

#----------------------------------------------------------------------
#
# Check login and password against an ldap database
#
sub ldap_check_passwd {
        ($login, $passwd) = @_;

        my $ldap = Net::LDAP->new($ldapserver) || die "ldap: $@";
        my $mesg = $ldap->bind;
        
        if ($mesg->code) {
                syslog(LOG_ERR, "ldap anon bind error");
                return 0;
        }
        $mesg = $ldap->search(base=>'dc=laas,dc=fr', filter=>"(uid=$login)");
        if ($mesg->code || $mesg->count != 1) {
                syslog(LOG_ERR, "ldap search error for $login: %d %d",
		       $mesg->code, $mesg->count);
                $ldap->unbind;
                return 0;
        }
        my $dn = $mesg->entry(0)->dn;
	
        $mesg = $ldap->bind("$dn", password=>"$passwd");
        if ($mesg->code) {
                syslog(LOG_ERR, "ldap bind error for $login");
                $ldap->unbind;  
                return 0;
        } 
        $ldap->unbind;
        return 1;
}

#----------------------------------------------------------------------
# 
# Validate input in the main login window: 
#
sub validate {
	my $q = $_[0];
	
	my $login = $q->param('login');
	my $password = $q->param('passwd');
	my $terms = $q->param('terms');
	my $ip = $q->remote_addr;
	
	if (defined($terms) && $terms == 'on') {
		if (ldap_check_passwd($login, $password)) {
			return "";
		} else {
			return "Incorrect login or password";
		}
	} else {
		return "You must accept the term of services";
	}
}

#----------------------------------------------------------------------
# 
# Send a request to the osapd daemon and wait for the answer
#
sub osapd_client {
	my $cmd = $_[0];
	
	socket(SOCK, PF_UNIX, SOCK_STREAM, 0) || return("socket: $!");
	connect(SOCK, sockaddr_un($sockname)) || return("connect: $!");
	SOCK->autoflush(1);

	print SOCK "$cmd\n" || return("print $!");
	my $result = <SOCK> || return("read $!");
	chop $result;
	print SOCK "QUIT\n" || return("quit $!");

	close SOCK;
	return $result;
}


#----------------------------------------------------------------------
# 
# Add the IP address of the client to the osap clients table in pf
#
sub add_user {
	my $q = $_[0];
	my $ip = $q->remote_addr;
	my $user = $q->param('login');
	syslog(LOG_INFO, "Add $user $ip");
	return osapd_client("ADD $ip $user");
}

#----------------------------------------------------------------------
#
# Remove the IP address of the client from the osap clients table in pf
#
sub del_user {
	my $q = $_[0];
	my $ip = $q->remote_addr;
	my $user = $q->param('login');
	syslog(LOG_INFO, "Del $user $ip");
	return osapd_client("DEL $ip");
}

#----------------------------------------------------------------------
#
# Test if the IP address of the client is already authorize
#
sub test_user {
	my $q = $_[0];
	my $ip = $q->remote_addr;
	syslog(LOG_INFO, "Test $ip");
	return osapd_client("TST $ip");
}

#----------------------------------------------------------------------  
#
# Main code
#
$q = new CGI;
setlogsock('unix');
openlog('osap', "ndelay,pid", LOG_DAEMON);

if ($q->request_method eq "GET") {
	# First time?
	my $name = test_user($q);
	if ($name ne "") {
		$q->param(-name=>'login', -value=>"$name");
		session_window($q);
	} else {
		login_window($q);
	}
} else {
	if ($q->param()) {
		my $which = $q->param('Disconnect');

		if ($which eq "Disconnect") {
			# ignore errors ??
			del_user($q);
			disconnected_window($q);
		} else {
			my $result = validate($q);
			if ($result ne "") {
				login_window($q);
				print $q->div({class=>'alert'}, $result);
			} else {
				my $pfresult = add_user($q);
				if ($pfresult eq "OK") {
					session_window($q);
				} else {
					# error
					login_window($q);
					print $q->div({class=>'alert'}, 
						      "'$pfresult'");
				}
			}
		}
	}
}
print $q->end_html, "\n";

exit 0;
