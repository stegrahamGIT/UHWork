use Modern::Perl;
use Mojo::UserAgent;

my $tokenExpiryTime;

# check to see if the correct cmd args have been provided
my $configArgs = &checkArgs(\@ARGV);

my $UPDATE = ${$configArgs}{"updateStatus"};
my $configFile = ${$configArgs}{"configFile"};

my %config;

# populate config hash
open (CONFIG, "<$configFile");
while (<CONFIG>) {
	chomp $_;
	my ($name,$value) = split('::',$_);
	$config{$name} = $value;
}
close CONFIG;

my $tokenURL = $config{"tokenURL"};
my $clientID = $config{"clientID"};
my $secret = $config{"secret"};
my $talisGUID = $config{"talisGUID"};
my $baseURL = $config{"baseURL"};
my $webBaseURL = $config{"webBaseURL"};
my $oldURLMatch = $config{"matchString"};
my $newURL = $config{"replacementURL"};
my $regexPattern = $config{"regexPattern"};
my $itemIDFile = $config{"itemIDFile"};

# read items IDs from file and store in an array
my @itemIDs;
if (-e $itemIDFile) {
	open (ITEMS, "<$itemIDFile");
	while (<ITEMS>) {
		next if ($_ =~ m/^#/); # ignore comments
		chomp $_;
		push @itemIDs, $_;
	}
	close ITEMS;
} else {
	print "Cannot find item ID file: $itemIDFile\n";
	exit;
}

my $logFile = "talisChangeLog.txt";
open (LOG, ">$logFile");

my $errorFile = "talisERRORLog.txt";
open (ERROR, ">$errorFile");

my $globalToken = &getToken($tokenURL,$clientID,$secret);

if (! defined $globalToken) {
	print "Cannot find token - token undefined\n";
	exit;
}

my $itemCount = 0;
my $resourceCount = 0;

# hold unique resource ID
my %resourceIDHash;

foreach my $item (@itemIDs) {
	$itemCount++;
	print LOG "Processing record $itemCount\n";
	my $endpoint = $baseURL . 'items/' . $item;
	print LOG "Item endpoint is $endpoint\n";
	print LOG "Web URL: " . $webBaseURL . "items/" . $item . "\n";
	my $resourceID = &getResourceID($endpoint,$globalToken);
	if (defined $resourceID) {
		print LOG "The resource ID is $resourceID\n";
		$resourceIDHash{$resourceID} = $resourceID;
	} else {
		print "Cannot retrieve resourceID for $item - see logs\n";
		print LOG "Cannot retrieve resourceID for $item\n";
		print ERROR "Cannot retrieve resourceID for $item\n";
	}
}

foreach my $resourceID (keys %resourceIDHash) {
	$resourceCount++;
	print $resourceCount . "\n";
	my $endpoint = $baseURL . 'resources/' . $resourceID;
	print LOG "Resource endpoint is $endpoint\n";
	my %addresses = &getWebAddress($endpoint,$globalToken);
	&changeURL(\%addresses,$oldURLMatch,$newURL,$regexPattern,$endpoint,$globalToken,$resourceID,$talisGUID);
	sleep 1;
}

close LOG;
close ERROR;

print "Processed $itemCount items\n";
print "Processed $resourceCount resources\n";

exit;

###################

sub checkArgs($) {

	my $argArray = $_[0];
	
	my %statusHash = (
		"update" => 1,
		"test" => 0
	);
	
	my %configHash;
	
	if ($#{$argArray} < 1) {
		
		print "Missing config file and/or update status\n";
		print "To run this script do: perl " . $0 . " <configFile> (test|update)\n";
		print "e.g. perl " . $0 . " talis.txt update\n";
		exit;
		
	} else {
		
		if (-e ${$argArray}[0]) {
			$configHash{"configFile"} = ${$argArray}[0];
			if (defined ${$argArray}[1]) {
				chomp(${$argArray}[1]);
				if ((${$argArray}[1] =~ /test/i) || (${$argArray}[1] =~ /update/i)) {
						$configHash{"updateStatus"} = $statusHash{${$argArray}[1]};
				} else {
						print ${$argArray}[1] . " is a unrecognised update status\n";
						print "Needs to be either test or update\n";
						exit;
				}
			} else {
				print "Please specifiy if this is a test run or update\n";
				print "For test run : perl " . $0 . " <configFile> test\n";
				print "For real run: perl " . $0 . " <configFile> update\n";
			}
		} else {
			print ${$argArray}[0] . " config file does does not exist\n";
			exit;
		}
	}
	
	return \%configHash;
}

###################

sub getToken($$$) {

	my $tokenURL = $_[0];
	my $clientID = $_[1];
	my $secret = $_[2];

	my $ua = Mojo::UserAgent->new;
	my $endpointURL = Mojo::URL->new($tokenURL)->userinfo($clientID . ":" . $secret);
	my $res = $ua->post($endpointURL => {} => form => {'grant_type' => 'client_credentials'})->result;
	
	my $token = undef;
	
	if ($res->is_success) {
		my $record = $res->json;
		$token = ${$record}{"access_token"};
		$tokenExpiryTime = time + 3300; # 55 mins
		print LOG "Token is $token\n";
	} else {
		print "Cannot retrieve token - see logs\n";
		print LOG "Cannot retrieve token\n";
		print LOG $res->body . "\n";
		print LOG $res->message . "\n";
		print ERROR "Cannot retrieve token\n";
		print ERROR $res->body . "\n";
		print ERROR $res->message . "\n";
		exit;
	}
	
	chomp($token);
	return $token;
}

##################

sub getResourceID($$) {

	my $endpoint = $_[0];
	my $token = $_[1];
	
	if (time > $tokenExpiryTime) {
		print LOG "The token has expired - get a new one\n";
		# using the global vars to pass to getToken 
		# rather than ones passed to this method
		$globalToken = &getToken($tokenURL,$clientID,$secret);
		$token = $globalToken;
	} 
	
	my $resourceID = undef;
	
	my %header = (
		'Authorization' => 'Bearer ' . $token,
		'cache-control' => 'no-cache'
	);
	
	my $ua = Mojo::UserAgent->new;
	my $res = $ua->get($endpoint => \%header)->result;
	
	if ($res->is_success) {
		my $record = $res->json;
		$resourceID = ${$record}{"data"}{"relationships"}{"resource"}{"data"}{"id"};
	} else {
		print "Cannot retrieve resourceID for $endpoint - see error log\n";
		print ERROR "Cannot retrieve resourceID for $endpoint\n";
		print ERROR $res->body . "\n";
		print ERROR $res->message . "\n";
	}
	
	return $resourceID;
}

###################

sub getWebAddress($$) {

	my $endpoint = $_[0];
	my $token = $_[1];
	
	if (time > $tokenExpiryTime) {
		print LOG "The token has expired - get a new one\n";
		# using the global vars to pass to getToken 
		# rather than ones passed to this method
		$globalToken = &getToken($tokenURL,$clientID,$secret);
		$token = $globalToken;
	} 
	
	my %addresses;
	
	my %header = (
		'Authorization' => 'Bearer ' . $token,
		'cache-control' => 'no-cache'
	);
	
	my $ua = Mojo::UserAgent->new;
	my $res = $ua->get($endpoint => \%header)->result;
	
	if ($res->is_success) {
		my $record = $res->json;
		# $address = ${$record}{"data"}{"attributes"}{"web_addresses"}[0];
		my $webAddresses = ${$record}{"data"}{"attributes"}{"web_addresses"};
		my $onlineResourceURL = ${$record}{"data"}{"attributes"}{"online_resource"}{"link"};
		# print "There are " . scalar @{$webAddresses} . " addresses in the array\n";
		
		$addresses{"webaddresses"} = $webAddresses;
		$addresses{"onelineresourceurl"} = $onlineResourceURL;
		
	} else {
		print "Cannot find web address for $endpoint\n";
		print LOG "Cannot find web address for $endpoint\n";
		print ERROR "Cannot find web address for $endpoint\n";
	}
	return %addresses;
}

##################

sub changeURL($$$$$$$$) {

	my $talisData = $_[0];
	my $oldURLMatch = $_[1];
	my $newURL = $_[2];
	my $regexPattern = $_[3];
	my $link = $_[4];
	my $token = $_[5];
	my $resourceID = $_[6];
	my $userID = $_[7];
	
	if (time > $tokenExpiryTime) {
		print LOG "The token has expired - get a new one\n";
		# using the global vars to pass to getToken 
		# rather than ones passed to this method
		$globalToken = &getToken($tokenURL,$clientID,$secret);
		$token = $globalToken;
	} 
	
	my $resourceisbn = "ISBN";
	
	my @newWebAddresses;
	
	# deal with Resource URL First
	my $resourceURL = %{$talisData}{"onelineresourceurl"};
	print LOG "Resource URL: $resourceURL \n";
	
	if ($resourceURL =~ m/$oldURLMatch/) {
			$resourceURL =~ m/$regexPattern/;
			$resourceisbn = $1;
			if ($resourceisbn !~ m/^[0-9]/) {
				print LOG "Cannot find in ISBN in resource URL\n";
			}
			print LOG "The Resource ISBN  is " . $resourceisbn . "\n";
			$resourceURL = $newURL . $resourceisbn;
	}
	
	# now deal with the Web Addresses - there can be more than one
	my $isbn = "ISBN";
	my $addresses = %{$talisData}{"webaddresses"};
	
	foreach my $address (@{$addresses}) {
		
		if ($address =~ m/$oldURLMatch/) {
			$address =~ m/$regexPattern/;
			$isbn = $1;
			if ($isbn !~ m/^[0-9]/) {
				print LOG "Cannot find ISBN\n";
			}
			print LOG "The ISBN is " . $isbn . "\n";
			$newURL = $newURL . $isbn;
			push @newWebAddresses, '"' . $newURL . '"';
		} else {
			push @newWebAddresses, '"' . $address . '"';
		}
	}
	
	# turn array into String for JSON data
	my $webAddressString = join(",", @newWebAddresses);
	
	print LOG "The updating web string " . $webAddressString . "\n";
	
	if ($isbn =~ m/^[0-9]/) {

		my $changeString = '{"data": 
								{ 
									"id": "' . $resourceID . '", 
									"type": "resources", 
									"attributes": 
										{ 
											"web_addresses": [ ' . $webAddressString . ' ], 
											"online_resource": 
												{ "source": "uri", "link": "' . $resourceURL . '" } 
										} 
								} 
							}';
	
		print LOG "Sending change:" . $changeString . "\n";
		print LOG "Sending request to $link\n";
		
		if ($UPDATE) {
	
			my %header = (
				'Content-Type' => 'application/json',
				'Authorization' => 'Bearer ' . $token,
				'X-Effective-User' => $userID,
				'cache-control' => 'no-cache'
			);
	
			my $ua = Mojo::UserAgent->new;
			my $res = $ua->patch($link => \%header => $changeString)->result;

			if ($res->is_success) {
				# what do we want to do - anything?
				# just print to log for the time being
				print LOG $res->body;
				print LOG "\n\n\n";
			} else {
				print LOG "##########\n";
				print LOG "ERROR\n";
				print LOG $res->body;
				print LOG $res->message;
				print LOG "\n########\n";
			}
		}
		
	} else {
		print ERROR "Not updated: Cannot find ISBN for " . $resourceID . "\n";
	} 
}
