#!/usr/bin/perl

# (C) Nginx, Inc.
# Copyright (C) Intel, Inc.
# Tests for syslog.
# Various log levels emitted with limit_req_log_level.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

plan(skip_all => 'win32') if $^O eq 'MSWin32';

my $t = Test::Nginx->new()->has(qw/http limit_req/)->plan(59);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

error_log syslog:server=127.0.0.1:%%PORT_8081_UDP%% info;
error_log %%TESTDIR%%/f_glob.log info;

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    limit_req_zone $binary_remote_addr zone=one:1m rate=1r/m;

    log_format empty "";
    log_format logf "$uri:$status";

    error_log syslog:server=127.0.0.1:%%PORT_8082_UDP%% info;
    error_log %%TESTDIR%%/f_http.log info;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location /e {
            error_log syslog:server=127.0.0.1:%%PORT_8084_UDP%%;
        }
        location /a {
            access_log syslog:server=127.0.0.1:%%PORT_8084_UDP%%;
        }
        location /ef {
            error_log syslog:server=127.0.0.1:%%PORT_8084_UDP%%,facility=user;
        }
        location /es {
            error_log syslog:server=127.0.0.1:%%PORT_8084_UDP%%,severity=alert;
        }
        location /et {
            error_log syslog:server=127.0.0.1:%%PORT_8084_UDP%%,tag=SEETHIS;
        }
        location /af {
            access_log syslog:server=127.0.0.1:%%PORT_8084_UDP%%,facility=user;
        }
        location /as {
            # put severity inside to catch possible parsing programming errors
            access_log syslog:severity=alert,server=127.0.0.1:%%PORT_8084_UDP%%;
        }
        location /at {
            access_log syslog:server=127.0.0.1:%%PORT_8084_UDP%%,tag=SEETHIS;
        }
        location /e2 {
            error_log syslog:server=127.0.0.1:%%PORT_8084_UDP%%;
            error_log syslog:server=127.0.0.1:%%PORT_8084_UDP%%;
        }
        location /a2 {
            access_log syslog:server=127.0.0.1:%%PORT_8084_UDP%%;
            access_log syslog:server=127.0.0.1:%%PORT_8084_UDP%%;
        }
        location /a_logf {
            access_log syslog:server=127.0.0.1:%%PORT_8084_UDP%% logf;
        }
        location /if {
            access_log syslog:server=127.0.0.1:%%PORT_8083_UDP%% logf
                if=$arg_logme;
        }

        location /nohostname {
            access_log syslog:server=127.0.0.1:%%PORT_8084_UDP%%,nohostname;
        }

        location /debug {
            limit_req zone=one;
            error_log syslog:server=127.0.0.1:%%PORT_8084_UDP%% debug;
        }
        location /info {
            limit_req zone=one;
            limit_req_log_level info;
            error_log syslog:server=127.0.0.1:%%PORT_8084_UDP%% info;
        }
        location /notice {
            limit_req zone=one;
            limit_req_log_level notice;
            error_log syslog:server=127.0.0.1:%%PORT_8084_UDP%% notice;
        }
        location /warn {
            limit_req zone=one;
            limit_req_log_level warn;
            error_log syslog:server=127.0.0.1:%%PORT_8084_UDP%% warn;
        }
        location /error {
            limit_req zone=one;
            limit_req_log_level error;
            error_log syslog:server=127.0.0.1:%%PORT_8084_UDP%%;
        }
        location /low {
            error_log syslog:server=127.0.0.1:%%PORT_8084_UDP%% warn;
            error_log syslog:server=127.0.0.1:%%PORT_8084_UDP%%;
        }
        location /dup {
            error_log syslog:server=127.0.0.1:%%PORT_8084_UDP%%;
            error_log syslog:server=127.0.0.1:%%PORT_8084_UDP%%;
        }
        location /high {
            error_log syslog:server=127.0.0.1:%%PORT_8084_UDP%% emerg;
            error_log syslog:server=127.0.0.1:%%PORT_8084_UDP%%;
        }
    }
}

EOF

$t->run_daemon(\&syslog_daemon, port(8081), $t, 's_glob.log');
$t->run_daemon(\&syslog_daemon, port(8082), $t, 's_http.log');
$t->run_daemon(\&syslog_daemon, port(8083), $t, 's_if.log');

$t->waitforfile($t->testdir . '/s_glob.log');
$t->waitforfile($t->testdir . '/s_http.log');
$t->waitforfile($t->testdir . '/s_if.log');

$t->run();

###############################################################################

parse_syslog_message('error_log', get_syslog('/e'));
parse_syslog_message('access_log', get_syslog('/a'));

like(get_syslog('/ef'), qr/^<11>/, 'error_log facility');
like(get_syslog('/es'), qr/^<187>/, 'error_log severity');
like(get_syslog('/et'), qr/SEETHIS:/, 'error_log tag');

like(get_syslog('/af'), qr/^<14>/, 'access_log facility');
like(get_syslog('/as'), qr/^<185>/, 'access_log severity');
like(get_syslog('/at'), qr/SEETHIS:/, 'access_log tag');


like(get_syslog('/e'),
	qr/nginx: \d{4}\/\d{2}\/\d{2} \d{2}:\d{2}:\d{2} \[error\]/,
	'error_log format');
like(get_syslog('/a_logf'), qr/nginx: \/a_logf:404$/, 'access_log log_format');

my @lines = split /<\d+>/, get_syslog('/a2');
is($lines[1], $lines[2], 'access_log many');

@lines = split /<\d+>/, get_syslog('/e2');
is($lines[1], $lines[2], 'error_log many');

# error_log log levels

SKIP: {

skip "no --with-debug", 1 unless $t->has_module('--with-debug');

isnt(syslog_lines('/debug', '[debug]'), 0, 'debug');

}

# charge limit_req

get_syslog('/info');

is(syslog_lines('/info', '[info]'), 1, 'info');
is(syslog_lines('/notice', '[notice]'), 1, 'notice');
is(syslog_lines('/warn', '[warn]'), 1, 'warn');
is(syslog_lines('/error', '[error]'), 1, 'error');

# count log messages emitted with various error_log levels

is(syslog_lines('/low', '[error]'), 2, 'low');
is(syslog_lines('/dup', '[error]'), 2, 'dup');
is(syslog_lines('/high', '[error]'), 1, 'high');

# check for the presence of the syslog messages in the global and http contexts

is_deeply(levels($t, 's_glob.log'), levels($t, 'f_glob.log'), 'master syslog');
is_deeply(levels($t, 's_http.log'), levels($t, 'f_http.log'), 'http syslog');

http_get('/if');
http_get('/if/empty?logme=');
http_get('/if/zero?logme=0');
http_get('/if/good?logme=1');
http_get('/if/work?logme=yes');

get_syslog('/a');

like($t->read_file('s_if.log'), qr/good:404.*work:404/s, 'syslog if success');
unlike($t->read_file('s_if.log'), qr/(if:|empty:|zero:)404/, 'syslog if fail');

like(get_syslog('/nohostname'),
	qr/^<(\d{1,3})>				# PRI
	([A-Z][a-z]{2})\s			# mon
	([ \d]\d)\s(\d{2}):(\d{2}):(\d{2})\s	# date
	(\w{1,32}):\s				# tag
	(.*)/x,					# MSG
	'nohostname');

###############################################################################

sub syslog_lines {
	my ($uri, $pattern, $port) = @_;
	return map { $_ =~ /\Q$pattern\E/g } (get_syslog($uri));
}

sub levels {
	my ($t, $file) = @_;
	my %levels_hash;

	map { $levels_hash{$_}++; } ($t->read_file($file) =~ /(\[\w+\])/g);

	return \%levels_hash;
}

sub get_syslog {
	my ($uri) = @_;
	my ($s);
	my $rfd = '';
	my $data = '';

	eval {
		local $SIG{ALRM} = sub { die "timeout\n" };
		local $SIG{PIPE} = sub { die "sigpipe\n" };
		alarm(1);
		$s = IO::Socket::INET->new(
			Proto => 'udp',
			LocalAddr => '127.0.0.1:' . port(8084)
		);
		alarm(0);
	};
	alarm(0);
	if ($@) {
		log_in("died: $@");
		return undef;
	}

	http_get($uri);

	vec($rfd, fileno($s), 1) = 1;
	select $rfd, undef, undef, 1;
	while (select($rfd, undef, undef, 0.1) > 0
		&& vec($rfd, fileno($s), 1))
	{
		my $buffer;
		sysread($s, $buffer, 4096);
		$data .= $buffer;
	}
	$s->close();
	return $data;
}

sub parse_syslog_message {
	my ($desc, $line) = @_;

	unless ($line) {
		fail("$desc timeout in receiving syslog");
	}

	my @months = ('Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug',
		'Sep', 'Oct', 'Nov', 'Dec');

	my ($pri, $mon, $mday, $hour, $minute, $sec, $host, $tag, $msg) =
		$line =~ /^<(\d{1,3})>				# PRI
			([A-Z][a-z]{2})\s			# mon
			([ \d]\d)\s(\d{2}):(\d{2}):(\d{2})\s	# date
			([\S]*)\s				# host
			(\w{1,32}):\s				# tag
			(.*)/x;					# MSG

	my $sev = $pri & 0x07;
	my $fac = ($pri & 0x03f8) >> 3;

	ok(defined($pri), "$desc has PRI");
	ok($sev >= 0 && $sev <= 7, "$desc valid severity");
	ok($fac >= 0 && $fac < 24, "$desc valid facility");

	ok(defined($mon), "$desc has month");
	ok((grep $mon, @months), "$desc valid month");

	ok(defined($mday), "$desc has day");
	ok($mday <= 31, "$desc valid day");

	ok(defined($hour), "$desc has hour");
	ok($hour < 24, "$desc valid hour");

	ok(defined($minute), "$desc has minutes");
	ok($minute < 60, "$desc valid minutes");

	ok(defined($sec), "$desc has seconds");
	ok($sec < 60, "$desc valid seconds");

	ok(defined($host), "$desc has host");
	chomp(my $hostname = lc `hostname`);
	is($host , $hostname, "$desc valid host");

	ok(defined($tag), "$desc has tag");
	like($tag, qr'\w+', "$desc valid tag");

	ok(length($msg) > 0, "$desc valid CONTENT");
}

###############################################################################

sub syslog_daemon {
	my ($port, $t, $file) = @_;

	my $s = IO::Socket::INET->new(
		Proto => 'udp',
		LocalAddr => "127.0.0.1:$port"
	);

	open my $fh, '>', $t->testdir() . '/' . $file;
	select $fh; $| = 1;

	while (1) {
		my $buffer;
		$s->recv($buffer, 4096);
		print $fh $buffer . "\n";
	}
}

###############################################################################
