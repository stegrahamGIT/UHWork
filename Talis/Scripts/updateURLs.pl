use Modern::Perl;
use Mojo::UserAgent;

# 1 will update
# 0 will do everything else but will not update
my $UPDATE = 1;
my $LIVE = 1;

my $tokenURL = "https://users.talis.com/oauth/tokens";
my $configFile;
my %config;

if ($LIVE) {
	print "Updating items for the live environment\n";
	$configFile = "liveConfig.txt";
} else {
	print "Updating items for the sandbox environment\n";
	$configFile = "sandboxConfig.txt";
}

# populate config hash
open (CONFIG, "<$configFile");
while (<CONFIG>) {
	chomp $_;
	my ($name,$value) = split('::',$_);
	$config{$name} = $value;
}
close CONFIG;

my $clientID = $config{"clientID"};
my $secret = $config{"secret"};
my $talisUID = $config{"talisUID"};
my $baseURL = $config{"baseURL"};
my $webBaseURL = $config{"webBaseURL"};
my $oldURLMatch = $config{"matchString"};
my $newURL = $config{"replacementURL"};
my $regexPattern = $config{"regexPattern"};

# read items IDs from file
my @itemIDs;
my $itemIDFile = "talisitemIDs.txt";
open (ITEMS, "<$itemIDFile");
while (<ITEMS>) {
    next if ($_ =~ m/^#/); # ignore comments
	chomp $_;
	push @itemIDs, $_;
}
close ITEMS;

my $logFile = "talisChangeLog.txt";
open (LOG, ">$logFile");

my $errorFile = "talisERRORLog.txt";
open (ERROR, ">$errorFile");

# get the token - remember this will only last for 1 hour
# if the update will last longer then the script will fail
# at the hour mark.
my $token = &getToken($tokenURL,$clientID,$secret);

if (! defined $token) {
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
	my $resourceID = &getResourceID($endpoint,$token);
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
	my %addresses = &getWebAddress($endpoint,$token);
	
	if ($UPDATE) {
		&changeURL(\%addresses,$oldURLMatch,$newURL,$regexPattern,$endpoint,$token,$resourceID,$talisUID);
		sleep 1;
	}
}

close LOG;
close ERROR;

print "Processed $itemCount items\n";
print "Processed $resourceCount resources\n";

exit;

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
	} else {
		print ERROR "Not updated: Cannot find ISBN for " . $resourceID . "\n";
	} 
}
