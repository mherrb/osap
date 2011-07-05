#!/usr/bin/perl -T --  # -*-Perl-*-
use CGI qw/:standard/;
use CGI::Pretty qw(:html3);
use CGI::Carp;
use Socket;
use IO::Handle;
use Net::DNS;

use Sys::Syslog qw(:standard :extended);

#----------------------------------------------------------------------
# Configuration section
#
$sockname =   '/tmp/osap.socket';	# name of Unix socket of osapd.pl
 
#----------------------------------------------------------------------	
#
# Create the main login window
#
sub login_window
{
	my $q = @_[0];
	
	print $q->header, $q->start_html(-title=>'OSAP Login',
					 -style=>{-src=>'/osap/osap.css'});
	
	print $q->h1('LAAS visitor\'s network.');
	print $q->start_form;
	print $q->start_table({-width=>'100%'},{-border=>'0'});
	print $q->Tr($q->td({align=>CENTER}, $q->img({src=>'/osap/Logo-LAAS-CNRS-400.png', 
				     width=>'400', 
				     height=>'81'})));
	my $register_widget = $q->table({-border=>'0'},
		$q->Tr($q->td({-colspan=>2, -align=>LEFT}, 
		'Welcome to the LAAS visitor network.<BR>To enable your access please enter your name and e-mail address below:')),
		$q->Tr($q->td({-align=>RIGHT}, 'Name:'),
			$q->td($q->textfield({-size=>50, name=>'name'}))),
		$q->Tr($q->td({-align=>RIGHT}, 'E-mail:'),
			$q->td($q->textfield({-size=>50, name=>'email'}))));
	print $q->Tr($q->td({align=>CENTER}, $register_widget));
	my $read_terms="I've read and accepted the ";
	my $terms_link=$q->a({-href=>'/osap/terms.html'}, 'terms of service');
	print $q->Tr($q->td({-colspan=>2, align=>CENTER},
			    $q->checkbox({-name=>'terms', 
					  -class=>'oswap-checkbox',
					  -label=>$read_terms}),
			    $terms_link));
	my $connect_button = $q->table(
		$q->Tr($q->td($q->submit({-name=>OK, -value=>Cancel,
				-class=>'oswap-button-cancel'})),
			$q->td($q->submit({-name=>OK, -value=>Connect,
				-class=>'oswap-button-ok'}))));
	print $q->Tr($q->td({align=>RIGHT}, $connect_button));
	print $q->end_table, "\n";
	print $q->end_form, "\n";
	print $q->div({-align=>RIGHT}, "sysadmin\@laas.fr"), "\n";
}

#----------------------------------------------------------------------
# 
# Create the 'session' window, displayed while the connection is active
#
sub session_window {
	my $q = $_[0];
	my $ip = $q->remote_addr;
	my $name = $q->param('name');
	my $email = $q->param('email');
	
	syslog(LOG_INFO, "session: \'$name\', \'$email\', $ip");
	print $q->header, $q->start_html(-title=>'LAAS network',
					 -style=>{-src=>'/osap/osap.css'});
	print $q->start_form;
	print $q->h2({align=>CENTER}, "You are connected to  the LAAS network.");
	print $q->h3({align=>CENTER}, "Please keep this window open.");
	print $q->p("&nbsp;Once you want to disconnect from the network, ",
	    "click on the button below:");
	print $q->p("You can add this page to your bookmarks to come ",
		   "back here later.");
	print $q->p("If you are a member of the LAAS and are using this ",
		"machine to connect on a regular basis, you should register ",
		"it with sysadmin.");
	print $q->p("If your machine is already registered, you should ",
		"use the WIFI network id that was given to you ",
		"instead of ", $q->b("laas-welcome"), ".");
	print $q->start_table({width=>'100%'});
	print $q->Tr({align=>CENTER},
		     $q->td($q->submit({-name=>'OK', -value=>'Disconnect',
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
	
	print $q->header, $q->start_html(-title=>'Disconnected',
					 -style=>{-src=>'/osap/osap.css'});
	print $q->start_form;
	print $q->h2({align=>CENTER}, "Disconnected.");
	print $q->p("&nbsp;Thank you for using the LAAS Network.");
	print $q->p("&nbsp;You are now disconnected.");
	print $q->start_table({width=>'100%'});
	print $q->Tr({align=>CENTER},
		     $q->td($q->submit({-name=>'OK', -value=>'Reconnect',
					-class=>'oswap-button-ok'})));
	print $q->end_table;
	print $q->end_form;
}

#----------------------------------------------------------------------
#
# Check e-mail address 
#
sub valid_email
{
	my $addr = $_[0];
	
	if ($addr =~ /^(\w|\-|\_|\.|\+)+\@(((\w|\-|\_)+\.)+[a-zA-Z]{2,})$/) {
		$domain = "$2";
		my $query = $resolver->search($domain);
		if ($query) {
			return 1;
		} else {
			my @mx = mx($resolver, $domain);
			if (@mx) {
				return 1;
			} else {
				syslog(LOG_INFO, "valid_email \'$addr\': can't find RR for $domain");
				return 0;
			}
		}
	} else {
		return 0;
	}
}

#----------------------------------------------------------------------
# 
# Validate input in the main login window: 
#
sub validate {
	my $q = $_[0];
	
	my $name = $q->param('name');
	my $email = $q->param('email');
	my $terms = $q->param('terms');
	my $ip = $q->remote_addr;

	syslog(LOG_DEBUG, "validate \'$name\', \'$email\', $ip");
	if ($name eq "") {
		return "Please fill the \'Name\' field.";
	}
	if ($email eq "") {
		return "Please fill the \'E-mail\' field.";
	}
	if (!valid_email($email)) {
		return "Please use a valid \'E-mail\' address.";
	}
	if (!defined($terms) || $terms ne 'on') {
		return "Please accept the term of services.";
	}
	return "";
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
	my $email = $q->param('email');
	my $name = $q->param('name');
	my $user = "$name/$email";
	$user =~ s/\s+/_/g;
	$user = escapeHTML($user);

	syslog(LOG_DEBUG, "Add $ip $user");
	return osapd_client("ADD $ip $user");
}

#----------------------------------------------------------------------
#
# Remove the IP address of the client from the osap clients table in pf
#
sub del_user {
	my $q = $_[0];
	my $ip = $q->remote_addr;

	syslog(LOG_DEBUG, "Del $ip");
	return osapd_client("DEL $ip");
}

#----------------------------------------------------------------------
#
# Test if the IP address of the client is already authorized
#
sub test_user {
	my $q = $_[0];
	my $ip = $q->remote_addr;

	syslog(LOG_DEBUG, "Test $ip");
	return osapd_client("TST $ip");
}

#----------------------------------------------------------------------  
#
# Main code
#
$q = new CGI;
setlogsock('unix');
openlog('osap', "ndelay,pid", LOG_DAEMON);
$resolver = Net::DNS::Resolver->new;

# print $q->a(href=\"{-noScript=>"terms.htm", -script=>"javascript:popup('terms.html')"\", "Terms");

if ($q->request_method eq "GET") {
	# First time?
	my $email = test_user($q);
	if ($email ne "") {
		$q->param(-name=>'email', -value=>"$email");
		session_window($q);
	} else {
		login_window($q);
	}
} else {
	if ($q->param()) {
		my $which = $q->param('OK');

		if ($which eq "Disconnect") {
			# ignore errors ??
			del_user($q);
			disconnected_window($q);
	 	} elsif ($which eq "Cancel") {
			disconnected_window($q);
		} elsif ($which eq "Reconnect") {
			login_window($q);
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
