#! /usr/bin/perl
use Sys::Syslog qw(:standard :extended);

setlogsock('unix');
openlog('osap', "pid", LOG_DAEMON) ||  die "openlog: $!";
syslog(LOG_INFO, "Test 1 2 3");
exit(0);
