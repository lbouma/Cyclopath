
# FIXME: Bugs for 1) managing user accts from flashclient, and
  #               2) inlining wiki text help.

MediaWiki login and account creation:

https://www.mediawiki.org/wiki/API

https://www.mediawiki.org/wiki/API:Account_creation

FIXME: No support for changing password... oh, well...
or maybe you can do it from raw api command?:
https://www.mediawiki.org/wiki/API:Calling_internally

FIXME: Get wiki page for help text, and *compile* info flashclient.
var x: MediaWikiCaller = new  MediaWikiCaller("Url To MediaWiki");
x.getContentPage("Montpellier"); 
#
ok, parse mediawiki w/ python. use the flex library just for user account stuff
https://www.mediawiki.org/wiki/Alternative_parsers

okay, maybe python can do the api calls...
https://github.com/btongminh/mwclient
https://code.google.com/p/python-wikitools



cd /ccp/opt/.downloads
svn checkout http://mediawiki-flash4-library.googlecode.com/svn/trunk mediawiki-flash4-library
cd /ccp/opt/.downloads/mediawiki-flash4-library
# This is weird: a preceeding space.
mv \ mediawiki-flash4-library mediawiki-flash4-library



move tsp code here

