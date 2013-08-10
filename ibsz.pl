#!/usr/bin/env perl
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

#Import DynECT handler
use FindBin;
use lib $FindBin::Bin;  # use the parent directory
require DynECT::DNS_REST;

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
	print "Additional details in README.md\n";
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

if ( $configopt{'cn'} eq 'CUSTOMERNAME' ) {
	print "Please modify config.cfg with account details\n";
	exit;
}

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

if ( defined $configopt{'tsig'} ) {
	delete $configopt{'tsig'} if ($configopt{'tsig'} eq 'TSIGKEYNAME');
}
if ( defined $configopt{'contact'} ) {
	delete $configopt{'contact'} if ($configopt{'contact'} eq 'CONTACT_NICK');
}

#Instantiate dynect library instance
my $dynect = DynECT::DNS_REST->new();

#API login
$dynect->login( $apicn, $apiun, $apipw )
	or die $dynect->message;

#Open file containing zone names
open my $file, '<', $opt_file
	or die "Unable to open file $opt_file.  Stopped";

#array for storing zone names
my @zones;
#Parse file for secondary zone names and post them to DynECT
while (<$file>) {
	my $zone_name = $_;
	#next if blankline
	next if $zone_name =~ /^\s*$/;
	chomp $zone_name;
	push ( @zones, $zone_name );
	#Create new secondary zone. Include TSIG key if one is specified
	my $zonerecord_uri = "/REST/Secondary/$zone_name/";

	my %api_param = ( 'masters' => @apimaster );
	$api_param{ 'tsig_key_name' } = $configopt{'tsig'} if ($configopt{'tsig'});
	$api_param{ 'contact_nickname' } = $configopt{'contact'} if ($configopt{'contact'});
	unless( $dynect->request( $zonerecord_uri, 'POST', \%api_param ) ) {
		die $dynect->message unless ( $dynect->message =~ /You already have this zone/);
		print "$zone_name : Already exists\n";
	}
	else { 
		print "$zone_name : Created\n";
	}
}

#Array to track 20 job slots
my @count = qw( -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 );
my @zone_name;

my $jobs = 0;
#while jobs are processing or zones still left
while ( $jobs || @zones) { 
	for my $i (0 .. $#count) {
		#if open slots
		if ( $count[$i] == -1 ) {
			#skips to next if there are no zones left
			next unless @zones;
			my %api_param = ( activate => 1 );
			$zone_name[$i] = shift @zones;
			$dynect->request( "/REST/Secondary/$zone_name[$i]/", 'PUT', \%api_param ) or die $dynect->message;
			$jobs++;
			$count[$i]++;
		}
		elsif ( $count[$i] > -1 ) { 
			$dynect->request ( "/REST/Secondary/$zone_name[$i]/", 'GET') or die $dynect->message;
			if ( $dynect->result->{'data'}{'active'} eq 'L' ) {
				$count[$i]++;
				print "$zone_name[$i] : Still working\n" if ( ( $count[$i] % 5 ) == 0 );
			}
			elsif ( $dynect->result->{'data'}{'active'} eq 'Y' ) {
				print "$zone_name[$i] : Actived\n";
				$count[$i] = -1;
				$jobs--;
			}
			else {
				print "$zone_name[$i] : Failed Activation\n";
				$count[$i] = -1;
				$jobs--;
			}
		}
		sleep 1;
	}
} 

