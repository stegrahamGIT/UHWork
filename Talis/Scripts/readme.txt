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

Step 1: Use the "All List Items" report from the Talis admin area to download a list of all items. Filter this list in Excel only to show VLE Book records. Copy the Items IDs into a file. This file is referenced in the  updateURLs.pl script by the $itemIDFile variable. The default value is talisitemIDs.txt.

Step 2: Make sure that all the values in the config file have been entered - oauth credentials, URLs and regex patterns. The config file for a sandbox environement by default is set to sandboxConfig.txt, and the live environemnt is liveConfig.txt. Set $LIVE to 0 for sandbox and to 1 for live changes.

Step 3: run the script "perl updateURLs.pl".

What the script does
--------------------

Using the items IDs in the talisitemIDs.txt file, the script create a unique hash of resource IDs. The resources IDs are iterated over and two URLs retrieved from the Talis JSON record:

web_addresses - can be more than one, so is saved in an array
online_resource->link - saved in a simple scalar variable

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

see https://rl.talis.com/3/docs for Talis API doc
