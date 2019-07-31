# Talis API

##############

N.B. The updateURLs.pl script has only been tested with changing Askew and Holts URLs.

The original URLs look like:

https://shibboleth2sp.gar.semcs.net/Shibboleth.sso/Login?entityID=https%3A%2F%2Fidp.herts.ac.uk%2Fshibboleth&amp;target=https%3A%2F%2Fshibboleth2sp.gar.semcs.net%2Fshib%3Fdest%3Dhttp%253A%252F%252Fwww.vlebooks.com%252FSHIBBOLETH%253Fdest%253Dhttp%25253A%25252F%25252Fwww.vlebooks.com%25252Fvleweb%25252Fproduct%25252Fopenreader%25253Fid%25253DHerts%252526isbn%25253D9781316665343

, and are changed to look like:

http://www.vlebooks.com/vleweb/product/openreader?id=Herts&isbn=9781316665343

The script uses a regular expression to retrieve the ISBN from the original URL, and uses it to construct the new link.

#############

Workflow
--------

Step 1: Use the "All List Items" report from the Talis admin area to download a list of all items. Filter this list in Excel to show only VLE Book records. Copy the Items IDs into a text file - each ID seperated by a line return. This file is referenced in the config file with the itemIDFile value.

Step 2: Make sure that all the values in the config file have been entered - oauth credentials, file names, URLs and regex patterns. This file is passed to the script as the first cmd line argument.

Step 3: run the script. The script requires two arguments:

argument one - the name/path of the config file populated in step 2.

argument two - either 'test' or 'update'. Test does everything apart from actually update the record. (Might be useful for testing? - the log file contains lots of info)

To run the script in test mode with a config file called UHConfigFile.txt:

perl updateURLs.pl UHConfigFile.txt test

To run the script in update mode with a config file called UHConfigFile.txt:

perl updateURLs.pl UHConfigFile.txt update

What the script does
--------------------

Using the items IDs in the provided file, the script create a unique hash of resource IDs. The resources IDs are iterated over and two URLs retrieved from the Talis JSON record:

web_addresses - can be more than one, so is saved in an array
online_resource->link - saved in a simple scalar variable

The online_resource URL is checked against the matchString config value to see if this value is contained within the URL. So, for example, if the matchString value is 

shibboleth2sp.gar.semcs.net 

and the URL is 

https://shibboleth2sp.gar.semcs.net/Shibboleth.sso/Login?entityID=https%3A%2F%2Fidp.herts.ac.uk%2Fshibboleth&amp;target=https%3A%2F%2Fshibboleth2sp.gar.semcs.net%2Fshib%3Fdest%3Dhttp%253A%252F%252Fwww.vlebooks.com%252FSHIBBOLETH%253Fdest%253Dhttp%25253A%25252F%25252Fwww.vlebooks.com%25252Fvleweb%25252Fproduct%25252Fopenreader%25253Fid%25253DHerts%252526isbn%25253D9781316665343

then there would be a match. If there is a match then the regexPattern config value is used to capture the ISBN. The regex needs to contain a back reference so it can be captured in Perls inbuilt $1 variable (https://perldoc.perl.org/perlretut.html#Backreferences). Example:

https.*isbn%25253D(.*)

for the above URL would capture 9781316665343.

The captured ISBN is concatenated to the end of the replacementURL config value to make a URL like:

http://www.vlebooks.com/vleweb/product/openreader?id=Herts&isbn=9781316665343

The same is done to the URLs in the web_addresses array.

These URLs are used in the data posted back to the Talis API to update the record e.g (the ID is the resource ID):

```
{
	"data": {
		"id": "03C5ED09-8F8E-82E7-9F35-5DD25F3BCF7A",
		"type": "resources",
		"attributes": {
			"web_addresses": ["http://www.vlebooks.com/vleweb/product/openreader?id=Herts&isbn=9781316665343"],
			"online_resource": {
				"source": "uri",
				"link": "http://www.vlebooks.com/vleweb/product/openreader?id=Herts&isbn=9781316665343"
			}
		}
	}
}
```

Two log files are created:

talisChangeLog.txt - tries to capture all useful info for troubleshooting etc
talisERRORlog.txt - all errors, problems getting IDs, updating etc

Modules required
----------------

Modern::Perl
Mojo::UserAgent (i.e. Mojolicious) 

see https://rl.talis.com/3/docs for Talis API doc and more information
