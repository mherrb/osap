#! /usr/bin/perl -w
use DB_File;

tie(%foo, 'DB_File', "test.db", O_CREAT|O_RDWR, 0600, $DB_HASH);

$foo{'bar'} = 1;

delete($foo{'bar'});

if (defined($foo{'bar'})) {
	print("failed\n");
} else {
	print("ok\n");
}

untie(%foo);
