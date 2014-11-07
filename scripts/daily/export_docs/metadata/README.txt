
== Overview ==

There are many Shapefile metadata formats.

But there are few Shapefile metadata applications
for creating metadata files, i.e., txt files, xml,
html, etc.

== MN Shapefile Metadata ==

Fortunately, MN has an app for that.

(Which, unflexibly, runs on just Windows... but
Windows isn't hard to find, usually, and you'll
rarely ever need to run this app.)

=== Links ===

Minnesota Geographic Metadata Guidelines

Version 1.2 - October 7, 1998

http://www.mngeo.state.mn.us/committee/standards/mgmg/Mgmg1_2.pdf

Metadata Workgroup

http://www.mngeo.state.mn.us/workgroup/metadata/index.html

=== The EPA Metadata Editor (EME) ===

This is a new editor.

FIXME: 2012.10.20: Is MN going to be using this software going forward?

https://edg.epa.gov/EME/Home.htm

=== DataLogr ===

Download DataLogr

 http://www.mngeo.state.mn.us/chouse/datalogr.html

In the State Menu you'll find the group DataLogr
and two shortcuts:

 DataLogr 2.1
 DataLogr MGMG Converter

The DataLogr 2.1 application is used to create and
edit the *.lgr metadata files.

The DataLogr MGMG Converter can read *.lgr files
and same them as XML and HTML documents.

You'll notice that the HTML metedata shares a
strikingly resemblance to files on datafinder.org.

== Federal Shapefile Metadata (USGS) ==

=== tkme ===

==== Links ====

http://sco.wisc.edu/wisclinc/metatool/

http://geology.usgs.gov/tools/metadata/tools/doc/ctc/

http://geology.usgs.gov/tools/metadata/tools/doc/tkme.html

http://equi4.com/tclkit/download.html

==== Caveats ====

On 64-bit linux, don't expect the 64-bit tclkit to work.

I.e.,

 # NO: wget -N http://www.equi4.com/pub/tk/8.5.1/tclkit-linux-x86_64.gz

==== Download and Install and Execute ====

If DataLogr works for you, you shouldn't need to run tkme, but if
you find to see the ultimate metadata creator, check out tkme.

 cd /ccp/opt/.downloads
 wget -N http://www.equi4.com/pub/tk/8.5.1/tclkit-linux-x86.gz

 # The download is just a zipped executable.
 gunzip tclkit-linux-x86.gz
 chmod 775 tclkit-linux-x86

 # mv? /usr/local/bin/tclkit

 wget -N http://geology.usgs.gov/tools/metadata/tkme.kit
 ./tclkit-linux-x86 tkme.kit

Now run tkme

 cd /ccp/opt/.downloads
 ./tclkit-linux-x86 tkme.kit

You start with an empty file.

You can use the Add menu to add elements, i.e., starting with Metadata,
and then drilling down from there.

But to start with all of the elements instead (and then delete what
you don't want), go to Snippets > template.xml

And that's it!

Note that tkme is a good crash-course in seeing what all the metadata
fields are, but you'll rarely use them all (or even most of them).
And DataLogr conforms to standards used by the State of Minnesota.

