#!/usr/bin/perl
#    This script does a bulk import of secondary zones.
#    
#	 The zone name of each new secondary zone needs to be specified
#    in a text file containing one zone per line.
#
#    A configuration file called config.cfg containing DynECT
#	 login credentials, one or more masters, and optionally a
#    TSIG key should exist in the same directory.
#    The file config.cfg takes the format:
#
#    [Dynect]
#    cn: [customer name]
#    un: [username]
#    pw: [password]
#    ip: [one or more comma separated A or AAAA records]
#    tsig: [TSIG key]
#
#    Usage: %perl ibsz.pl -F FILE [options]
#
#    Options
#        -f, --file FILE         Specify the text file containing a list of zone names
#        -t, --tsig              Indicate whether TSIG key is included in config.cfg
#        -h, --help              Show this help message and exit

use warnings;
use strict;
use Config::Simple;
use Getopt::Long;
use LWP::UserAgent;
use JSON;

my $opt_file;
my $opt_help;
my $opt_tsig;

#Assign the values of each option to variables
GetOptions(
	'file=s'	=>	\$opt_file,
	'tsig'		=>  \$opt_tsig,
	'help'		=>	\$opt_help
);

#Print help message and exit
if ($opt_help) {
	print "This script does a bulk import of secondary zones. The zone name of\n";
	print "each secondary zone needs to be specified in a text file containing one\n";
	print "zone name per line.\n\n";
	print "A configuration file called config.cfg containing DynECT login\n";
	print "credentials, one or more masters, and optionally a TSIG key should\n";
	print "exist in the same directory. The file config.cfg takes the format:\n";
	print "[DynECT]\n";
	print "cn: [customer name]\n";
	print "un: [username]\n";
	print "pw: [password]\n";
	print "ip: [one or more comma separated A or AAAA records]\n";
	print "tsig: [TSIG key]\n\n";
	print "Options:\n";
	print "-f, --file FILE\t\tREQUIRED: Specify text file\n";
	print "-t, --tsig\t\tIndicate whether TSIG key is included in the cfg file\n";
	print "-h, --help\t\tPrints this help message and exits\n";
	exit;
}

#Exit if file is not specified
unless ($opt_file) {
	print "-f or --file option and valid file required\n";
	exit;
}

#Create config reader
my $cfg = new Config::Simple();

# read configuration file (can fail)
$cfg->read('config.cfg') or die $cfg->error();

#dump config variables into hash for later use
my %configopt = $cfg->vars();
my $apicn = $configopt{'cn'} or do {
	print "Customer Name required in config.cfg for API login\n";
	exit;
};

my $apiun = $configopt{'un'} or do {
	print "User Name required in config.cfg for API login\n";
	exit;
};

my $apipw = $configopt{'pw'} or do {
	print "User password required in config.cfg for API login\n";
	exit;
};

my @apimaster = $configopt{'ip'} or do {
	print "One or more IP address required in config.cfg\n";
	exit;
};

my $apitsig = $configopt{'tsig'} or do {
	if ($opt_tsig) {
		print "TSIG Key required in config.cfg when -t or --tsig option specified\n";
		exit;
	}
};

#API login
my $session_uri = 'https://api2.dynect.net/REST/Session';
my %api_param = ( 
	'customer_name' => $apicn,
	'user_name' => $apiun,
	'password' => $apipw,
	);
my $api_request = HTTP::Request->new('POST',$session_uri);
$api_request->header ( 'Content-Type' => 'application/json' );
$api_request->content( to_json( \%api_param ) );
my $api_lwp = LWP::UserAgent->new;
my $api_result = $api_lwp->request( $api_request );
my $api_decode = decode_json ( $api_result->content ) ;
my $api_key = $api_decode->{'data'}->{'token'};

#Open file containing zone names
open my $file, '<', $opt_file
	or die "Unable to open file $opt_file.  Stopped";

#Parse file for secondary zone names and post them to DynECT
while (<$file>) {
	my $zone_name = $_;
	chomp $zone_name;
	#Create new secondary zone. Include TSIG key if one is specified
	my $zonerecord_uri = "https://api2.dynect.net/REST/Secondary/$zone_name/";
	my $api_request = HTTP::Request->new('POST',$zonerecord_uri);
	$api_request->header( 'Content-Type' => 'application/json', 'Auth-Token' => $api_key );
	if ($apitsig) {
		my %api_param = ( 'masters' => @apimaster, 'tsig_key_name' => $configopt{'tsig'} );
		$api_request->content( to_json( \%api_param ) );
		my $api_result = $api_lwp->request($api_request);
		my $api_decode = decode_json( $api_result->content);
		$api_decode = &api_fail(\$api_key, $api_decode) unless ($api_decode->{'status'} eq 'success');
	}
	else {
		my %api_param = ( 'masters' => @apimaster );
		$api_request->content( to_json( \%api_param ) );
		my $api_result = $api_lwp->request($api_request);
		my $api_decode = decode_json( $api_result->content);
		$api_decode = &api_fail(\$api_key, $api_decode) unless ($api_decode->{'status'} eq 'success');
	}
}

#Fail gracefully
sub api_fail {
	my ($api_keyref, $api_jsonref) = @_;
	#set up variable that can be used in either logic branch
	my $api_request;
	my $api_result;
	my $api_decode;
	my $api_lwp = LWP::UserAgent->new;
	my $count = 0;
	#loop until the job id comes back as success or program dies
	while ( $api_jsonref->{'status'} ne 'success' ) {
		if ($api_jsonref->{'status'} ne 'incomplete') {
			foreach my $msgref ( @{$api_jsonref->{'msgs'}} ) {
				print "API Error:\n";
				print "\tInfo: $msgref->{'INFO'}\n" if $msgref->{'INFO'};
				print "\tLevel: $msgref->{'LVL'}\n" if $msgref->{'LVL'};
				print "\tError Code: $msgref->{'ERR_CD'}\n" if $msgref->{'ERR_CD'};
				print "\tSource: $msgref->{'SOURCE'}\n" if $msgref->{'SOURCE'};
			};
			#api logout or fail
			$api_request = HTTP::Request->new('DELETE','https://api2.dynect.net/REST/Session');
			$api_request->header ( 'Content-Type' => 'application/json', 'Auth-Token' => $$api_keyref );
			$api_result = $api_lwp->request( $api_request );
			$api_decode = decode_json ( $api_result->content);
			exit;
		}
		else {
			sleep(5);
			my $job_uri = "https://api2.dynect.net/REST/Job/$api_jsonref->{'job_id'}/";
			$api_request = HTTP::Request->new('GET',$job_uri);
			$api_request->header ( 'Content-Type' => 'application/json', 'Auth-Token' => $$api_keyref );
			$api_result = $api_lwp->request( $api_request );
			$api_jsonref = decode_json( $api_result->content );
		}
	}
	$api_jsonref;
}
