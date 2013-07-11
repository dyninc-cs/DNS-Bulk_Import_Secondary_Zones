#!/usr/bin/perl
#    This script does bulk imports of secondary zones.
#    
#	 The zone names of each new secondary zone should be specified in a text file,
#    with one per line.
#
#    DynECT login credentials, a TCIG key, and one or more masters should be specified
#    in a config.ini file.
#
#    [Dynect]
#    user: user_name
#    customer: customer_name
#    password: password
#    
#    Usage: %perl ibsz.pl [-F]
#
#    Options
#        -h, --help              Show this help message and exit
#        -F, FILE, --File=FILE   Specify the text file containing a list of zone names

use warnings;
use strict;
use Config::Simple;
use Getopt::Long;
use LWP::UserAgent;
use JSON;

my $opt_file;
my $opt_help;

GetOptions(
	'file=s'	=>	\$opt_file,
	'help'		=>	\$opt_help
);

#Prints help message
if ($opt_help) {
	print "\tThis script does bulk imports of secondary zones.\n\n";
	print "\tThe zone names of each new secondary zone should be specified\n";
	print "\tin a text file, with one per line.\n\n";
	print "\tDynECT login credentials, a TCIG key, and one or more masters\n";
	print "\tshould be specified in a config.ini file.\n\n";
	print "\tOptions:\n";
	print "\t\t--file/-f <FILE>\tREQUIRED: Text file\n";
	print "\t\t-help/-h\t\tPrints this help information\n";
	exit;
}

#Exit if file is not specified
unless ($opt_file) {
	print "-f or --file option required\n";
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

my $apitsig = $configopt{'tsig'} or do {
	print "TSIG Key required in config.cfg\n";
	exit;
};

my @apimaster = $configopt{'ip'} or do {
	print "One or more IP address required in config.cfg\n";
	exit;
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
if ($api_decode->{'status'} eq 'success') {
print "Login successful.\n";
}

#Open file
open my $file, '<', $opt_file
	or die "Unable to open file $opt_file.  Stopped";

#Parse file, assign content to variables
while (<$file>) {
	my $zone_name = $_;
	chomp $zone_name;
	
	#Create new secondary zone
	my $zonerecord_uri = "https://api2.dynect.net/REST/Secondary/$zone_name/";
	my $api_request = HTTP::Request->new('POST',$zonerecord_uri);
	$api_request->header( 'Content-Type' => 'application/json', 'Auth-Token' => $api_key );
	my %api_param = ( 'masters' => @apimaster, 'tsig_key_name' => $apitsig );
	$api_request->content( to_json( \%api_param ) );
	my $api_result = $api_lwp->request($api_request);
	my $api_decode = decode_json( $api_result->content);
	$api_decode = &api_fail(\$api_key, $api_decode) unless ($api_decode->{'status'} eq 'success');
}

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
