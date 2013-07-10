#!/usr/bin/perl

#    This script does bulk update changes to the IP address of your zone, by reading in a CSV file,
#    then Publishing the Zones that were updated trough the DynECT API.
#    
#    The format of the csv file is "Zone Name", "Old IPv4 Address", "New IPv4 Address",
#
#    The credentials are read in from a configuration file in 
#    the same directory. 
#    
#    The file is named credentials.cfg in the format:
#    
#    [Dynect]
#    user: user_name
#    customer: customer_name
#    password: password
#    
#    Usage: %python ipb.py [-F]
#
#    Options
#        -h, --help              Show this help message and exit
#        -F, FILE, --File=FILE   Add CSV file to search through for bulk IP address change.

use warnings;
use strict;
use Data::Dumper;
use Config::Simple;
use Getopt::Long;
use LWP::UserAgent;
use JSON;
use File::Slurp;
use File::Spec;
use Text::CSV_XS;

my $opt_file;
my $opt_help;

GetOptions(
  'file=s'	=>	\$opt_file,
	'help'		=>	\$opt_help
);

#This help message needs updating
if ($opt_help) {
	my $hmsg = <<'HELP';
	\tThis script imports and publishes zone files to DynECT\n
	\tAPI integration requires paramaters stored in config.cfg\n\n
	\tOptions:\n
	\t\t-file/-m \<FILE\>\tThe hostmaster mailbox associated with the zone\n\t\t\t\t\tOverrides value defined in config.cfg\n
	\t\t-xml/-x <FILE>\t\tREQUIRED: XML File to be interpreted\n
	\t\t-zone/-z \"ZONE\"\t\tREQUIRED: Zone name for matching XML file\n
	\t\t-help/-h\t\tPrints this help information\n
HELP
	exit;
}

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

my @apimaster = $configopt{'ip'} or do { #Debugging: Syntax for array MAY not work
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

#Open CSV file
open my $csvfile, '<', $opt_file
	or die "Unable to open XML File $opt_file.  Stopped";

#Create CSV file parser
my $csv = Text::CSV_XS->new ({ binary => 1 });

#Parse CSV file, assign content to variables
while (my $row = $csv->getline ($csvfile)) {
	my $zone_name = $$row[0];

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
