Welcome to Era Eight
--------------------

Era Eight is a free OPAC (Open Public Access Catalogue) add-on to the
Heritage library management software. It is not based on the Heritage
Online system, but provides a number of improvements over Heritage
Online:

    * It is free. You will never run out of Heritage licenses for your
      OPAC, because Era Eight doesn't use Heritage.

    * It is fast. Search results are returned in under a second.

    * It is beautiful. The look and feel is modelled on a familiar web
      search engine, and can be customized to match your organisation's
      home page.

    * It is relevant. Search results are aware of the popularity of book
      loans and place more popular books to the top.

    * It is helpful. If Google Books has a scanned copy of the book, Era
      Eight tells you about it. If Amazon knows about the book, Era
      Eight presents the description and photograph. It also gives you 
      bibliographic citations in Bibtex and Harvard formats.

    * It is customizable. Every page is made up of templates which can
      be customized to suit the needs of individual institutions. If you
      don't use Harvard citations, change the template to show the data
      in another format instead!

Era Eight is written by Simon Cozens and is released under the 
Artistic License version 2: 
http://www.opensource.org/licenses/artistic-license-2.0.php

Installation instructions 
-------------------------

Era Eight is written in a programming language called Perl, so first you
will need a copy of Perl. If you are on Linux, Mac OS X or any other
form of Unix, you will already have Perl; on Windows, you will need to
install Strawberry Perl. Get it from http://strawberryperl.com/ and
double click to install.

Era Eight also needs a number of other Perl modules installed, but 
it makes this easy by downloading and installing them for you. To do
this, open a console window, navigate to the Era Eight directory and
run "perl Makefile.PL" - then follow the prompts. Type "make" and the
installer will download and install the modules. 

 Note: If you are on Debian or Ubuntu, you can make life easier for
 yourself by installing a few packages first:
    sudo apt-get install libtemplate-perl libclass-dbi-sqlite-perl libhttp-server-simple-perl
 
 Note: There are currently some problems making Era Eight work on
 Windows. This is due to the upstream modules that E8 uses, not to E8
 itself. I'm working with the modules' authors to get this fixed.

Setting up the database
-----------------------

You will need access to your Heritage catalogue files. If you are running
EraEight on a separate machine to your Heritage server, you will need to
mount the server's Heri4 directory. Underneath the Heri4 directory there
is a directory called "windata". This contains your catalogue files.

From the Era Eight directory, run the following command to import the
database:

    perl import.pl $directory

where $directory is the directory containing the catalogue files. (i.e.
ending with "/heri4/windata")

You will also need to update the catalogue periodically - I suggest
around once per hour. On Windows, you can configure a "scheduled task"
from Start > Programs > Accessories > System Tools > Scheduled Tasks;
on Unix, run "crontab -e" and add the following line

    @hourly (cd $e8dir; perl import.pl $directory >/dev/null)

where $e8dir is the directory containing Era Eight and $directory is the
Heritage catalogue files as above.

Amazon Web Services key
-----------------------

In order to download book descriptions and pictures from Amazon, you'll
need an Amazon Web Services key and secret. Get this from
http://aws-portal.amazon.com/gp/aws/developer/account/index.html?action=access-key


Configuring the server
----------------------

Finally, you will need to configure your server. To do this, create a
file in your Era Eight directory called "e8-server.pl". (Future versions
will help you to do this, but we're not quite there yet.)

In the simplest case, your file should look like this:

    use lib "lib";
    use EraEight
        amazon_key_id => "... Amazon key here ...",
        amazon_secret_key => "... Amazon secret here ...",
        library_name => "My Institution",

This will start a search engine running on port 4848 of your server. To
change the port, add a line:

    port => 1234,

To run on the standard web server port, use

    port => 80,

and remember to run the server as a privileged user.

By default the server listens on all interfaces available; to restrict
it to a particular IP address, add a line:

    host => "123.4.5.6",

Running your server
-------------------

Now in the Era Eight directory, run:

    perl e8-server.pl

You should then be able to connect to port 4848 of your server in a web
browser. (http://yourserver.yourinstitution.org:4848/)

Enjoy Era Eight!

