#!/usr/bin/perl --  # -*-Perl-*-
use Socket;
use IO::Handle;

$sockname = '/tmp/osap.socket';

sub osapd_client {
  my $cmd = $_[0];

  socket(SOCK, PF_UNIX, SOCK_STREAM, 0) || return("socket: $!");
  connect(SOCK, sockaddr_un($sockname)) || return("connect: $!");
  SOCK->autoflush(1);
  print SOCK "$cmd\n" || return("print $!");
  my $result = <SOCK> || return("read $!");
  print SOCK "QUIT\n" || return("quit $!");
  close SOCK;
  return $result;
}


sub add_user {
  my $ip = $_[0];
  print STDERR "osap: add $ip\n";
  return osapd_client("ADD $ip");
}

sub del_user {
  my $ip = $_[0];;
  print STDERR "osap: remove $ip\n";
  return osapd_client("DEL $ip");
}

add_user("10.1.2.1");
