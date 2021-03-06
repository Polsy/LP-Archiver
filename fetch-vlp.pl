#!/usr/bin/perl

# Thread URL, if not already fetched into a file
$threadURL = "";

# Name the the game here - used as the main heading on the index page
# and the page title of updates
$gameName = "?";


# These following settings should be set to 1 to enable them,
# or to 0 to disable them

# Multiple videos on the same line are backups of the same video
$multiBackups = 1;


# You're unlikely to need to change the following settings

# Optional parameters specific to wget
# - Retry downloading files up to a maximum of 3 times
$wgetParms = "--tries=2";

# List of sites that contain videos (so any hrefs referring to these
# sites are most likely videos)
@videoSites = (['Dailymotion', 'dailymotion.com'   ],
               ['YouTube',     'youtube.com'       ],
               ['Google',      'video.google.[^/]+'],
               ['FileFront',   'filefront.com'     ],
               ['Viddler',     'viddler.com'       ],
               ['Vimeo',       'vimeo.com'         ],
               ['blip.tv',     'blip.tv'           ],
               ['Baldurdash',  'bd.baldurk.org'    ],
               ['Grimfiend',   'grimfiend.com'     ],
               ['C&I',         'chipandironicus.com'],
               ['SD.net',      'somethingdreadful.net'],
               ['DiscoShiny',  'discoshiny.com'    ]);

# These lines are required for Firefox and Chrome cookie handling
# Remove them if they cause problems but cookies may fail
use DBD::SQLite;
use File::Copy;

# Cookies for downloading threads from the forums:
# - Auto-detect by default (currently Windows-only)
if($^O eq "MSWin32") {
  $isWin32 = 1;
  ($uid, $pass) = &detectWinCookies;
} elsif($^O eq "darwin") {
  $isMacOS = 1;
  ($uid, $pass) = &detectMacCookies;

  # Set wget executable if it isn't already
  if(-f 'wget' && ! -x 'wget') {
    system("/bin/chmod u+x wget");
  }
  # Add the current directory to the path so wget works if it's there
  $ENV{'PATH'} = $ENV{'PATH'} . ':.';
} elsif(-f $ENV{"HOME"} . "/sacookies") {
  # - other OSes 'Auto-detect' effort, check ~/sacookies

  # Read file to $cookies
  local $/=undef;
  open COOKIES, $ENV{"HOME"} . "/sacookies" or die "Failed to open file $!";
  my $cookies = <COOKIES>;
  close COOKIES;

  # first two lines are uid and pass
  ($uid, $pass) = split("\n", $cookies);
}

# - or manual settings:
if(! $uid) {
  # username ('bbuserid' cookie)
  $uid = "123456";
  # password ('bbpassword' cookie)
  $pass = "65517c0bb4f3b05648502d1917fb2c6a";
}

$scriptStart = time;
print "Script started at ", scalar(localtime($scriptStart)), "\n\n";

# If no thread URL, and there isn't exactly one argument passed
# try to default to showthread.txt If that doesn't exist, fail
if(! $threadURL) {
  if($#ARGV != 0) {
    if(-f "showthread.txt") {
      $ARGV[0] = "showthread.txt";
    } else {
      print "Syntax: $0 filename\n";
      exit 1;
    }
  }
} else {
  &getThread($threadURL);
  $ARGV[0] = "autoFetchedThread.txt";
}


open(IN, "<$ARGV[0]") || die "Couldn't open file $ARGV[0]: $!\n";

# $upd: -1 is no updates, 0 is the OP
$upd = -1; $postBody = "";
$author = "?"; $firstDate = "?";
$threadName = "?"; $threadURL = "?";
$errors = "";
$vidCols = 1;

# Make subdirectory for images
mkdir "Images" || die $!;

# Go through the file until you hit a post, useful thing or the file ends
while(<IN>) {
  # Found a post!
  if(/<!-- BeginContentMarker -->/) {
    if($upd == 0) { # shouldn't be able to get here if we already
                    # got an update, but just in case
      last;
    }

    &getPost;
  }
  
  elsif($author eq "?" && /<dt class="author/) { # Post author
    ($author) = m#<dt class="author(?: op)?" title="">(.+)</dt>#;
  }

  elsif($firstDate eq "?" && /<td class="postdate">/) { # First post date
    $junk = <IN>; # blank line
    $junk = <IN>; # post number
    $junk = <IN>; # thread/user numbers
    $_ = <IN>; # actual date info
    ($firstDate) = m#(\w+ \d+, \d+) \d+:\d+#; 

    # Got the post's date - we're done
    last;
  }

  elsif(/<title>/) { # Thread name
    ($threadName) = m#^\s+<title>(.+) - The Something Awful Forums</title>#;
  }
  elsif(/<label>Search thread: /) { # Thread ID (generate URL)
    ($threadID) = m#name="threadid" value="(\d+)"#;
    $threadURL = "http://forums.somethingawful.com/showthread.php?threadid=$threadID";
  }
}
close(IN);

# Delete temporary file if we downloaded the thread ourselves
if($threadURL) { unlink 'autoFetchedThread.txt'; }


# Get the current date to use as the Date Added
use POSIX;
$addedDate = POSIX::strftime("%b %d, %Y", localtime(time));

# Create the index
open(IDX, ">index.html") || die "Couldn't create index: $!\n";

print IDX <<HEADER1;
<html>
<head>
<meta http-equiv="content-type" content="text/html; charset=utf-8" />
<meta http-equiv="content-language" content="en" />
</head>
<body>
<!-- NOTE: Don't change the layout of these, it will be parsed by a script. -->
<h1>Title: $gameName</h1>
<h1>Author: $author</h1>
<h1>Thread: $threadName</h1>
<h1>Begin Date: $firstDate</h1>
<h1>End Date: ---</h1>
<h1>Author Webpage: ---</h1>
HEADER1

print IDX "<h1>Num Updates: ", scalar(grep(!/^b/, @videoURLs)), "</h1> <!-- This is the number of videos for a video LP-->\n";

print IDX <<MAIN;

<!-- !!DO NOT REMOVE!! BEGIN_CONTENT !!DO NOT REMOVE!! -->
<h1>Introduction</h1>
$postBody
MAIN

if($#videoURLs > -1) {
  $vidSize = 0;

  print IDX <<VIDEOH;
<br><br><br>
<h1>Videos</h1>
<table>
<col width="99%">
VIDEOH

  $tblContent = "";

  for($i=0; $i<=$#videoURLs; $i++) {
    $URL = $videoURLs[$i]; $title = $videoTitles[$i];

    # Columns for video mirrors
    if($multiBackups) {
      ($t1, $t2) = ($title =~ /^([^`]+)`(.+)$/);
      if(! $t1) { $t1 = $title; $t2 = $title; }

      $tblContent .= qq#<tr><td>$t1</td><td><a href="$URL" target="_blank" rel="nofollow">$t2</a></td>\n#;

      my $curCols = 1;

      while($videoURLs[$i+1] =~ /^b/) {
        $i++;
        $curCols++;
        $URL = $videoURLs[$i]; $title = $videoTitles[$i];

        $URL =~ s/^b//;
        $tblContent .= qq#<td><a href="$URL" target="_blank" rel="nofollow">$title</a></td>\n#;
      }

      # ensure every row has the same number of cells
      while($curCols < $vidCols)
      {
        $curCols++;
        $tblContent .= qq#<td>&nbsp;</td>\n#;
      }
    } else {
      $tblContent .= qq#<tr><td><a href="$URL" target="_blank" rel="nofollow">$title</a></td>\n#;
    }

    $tblContent .= "</tr>\n";
  }  
  $tblContent .= "</table>\n\n";
}

# Dump table to file
print IDX $tblContent;

# Remove wget error file (if it was generated, either here or earlier)
unlink 'wgeterr.txt';


print IDX <<FOOTER;
<!-- !!DO NOT REMOVE!! END_CONTENT !!DO NOT REMOVE!! -->
</body>
</html>
FOOTER

close(IDX);

if($isWin32) {
  $winConsole->Title("Finished - $gameName");
}

if($vidSize) {
  $txt = sprintf "Total video size: %2.2f MB\n", ($vidSize / 1048576);
  print "\n$txt";
  open(V, ">stats.txt");
  print V $txt;
  close(V);
} else {
  unlink 'stats.txt';
}

if($errors) {
  print "\nErrors:\n";
  print $errors;

  open(V, ">>stats.txt");
  print V "\nErrors:\n";
  print V $errors;
  close(V);
}

$scriptEnd = time;
print "\nScript ended at ", scalar(localtime($scriptEnd)), "\n";
$elapsed = $scriptEnd - $scriptStart;
print "Elapsed time: ";
if($elapsed < 60) { print "$elapsed seconds\n"; }
else {
  $elapsedM = int($elapsed / 60); $elapsedS = $elapsed % 60;
  printf "$elapsedM minute%s, $elapsedS second%s\n",
         ($elapsedM == 1 ? "":"s"), ($elapsedS == 1 ? "":"s");
}

print "\nPress enter to finish\n";
$junk = <STDIN>;


# Subroutines

# Extract an entire post from a thread list, save the images

sub getPost {
  $upd++;
  $img = 0;
  undef %images;
  my @errimgs = qw();

  while(<IN>) {
    # Ignore these
    next if /<!-- google_ad_section_start -->/;
    next if /<!-- google_ad_section_end -->/;

    # End of post marker
    last if /<!-- EndContentMarker -->/;

    # Fix the line ending to match the downloader's platform
    # (to make editing the output files easier)
    tr/\r\n//d;
    $_ .= "\n";

    if(m#<a href=#) {
      # Take a copy of the line, as it gets deliberately broken later
      $lineCopy = $_;
      @newURLs = (); @newTitles = ();

      # Copy line for use as table row
      $lineTitle = $_; $lineTitle =~ tr/\r\n//d;
      # Strip HTML tags, except images
      $lineTitle =~ s#<img#!img#g;
      $lineTitle =~ s#</?[^>]+>##g;
      $lineTitle =~ s#!img#<img#g; 

      do {
        ($URL, $title) = m#<a href="(http://[^"]+)"[^>]+>([^<]+)</a>#;
        if(! $title) { # Can happen with image-only video links
          ($URL) = m#<a href="(http://[^"]+)"[^>]+>.+</a>#;
          $title = "(no title)";
        }

        # Video?
        $isVideo = 0;
        for $site (@videoSites) {
          if($URL =~ /$$site[1]/) { $isVideo = 1; $siteName = $$site[0]; }
        } 

        if($isVideo) {
          # Avoid duplicates
          $gotURL = 0;
          for($i=0; $i<=$#videoURLs; $i++) {
            if($videoURLs[$i] eq $URL ||
               $videoURLs[$i] eq "b$URL") { $gotURL = 1; }
          }

          if(! $gotURL) {
            if(@newURLs) {
              $URL = "b$URL";
            }
 
            if($multiBackups) {
              $title = $siteName;
            } else {
              $title = "$lineTitle | $siteName";
            }

            push(@newURLs, $URL); push(@newTitles, $title);
          }
        }

        # Stop this video from being processed again
        s#<a href#<x href#;
      } while($URL && m#<a href#);

      # Retrieve the original line (with its a hrefs intact)
      $_ = $lineCopy;

      if(@newURLs) {
        if($multiBackups) {
          $newTitles[0] = "$lineTitle`$newTitles[0]";
        }

        push(@videoURLs, @newURLs); push(@videoTitles, @newTitles);

        # Check number of columns
        if(scalar(@newURLs) > $vidCols) { $vidCols = scalar(@newURLs); }
      }
    }

    # Catch images (and take a copy of the post) - first post only!
    if($upd == 0) {
      # loop in case there's multiple images on one line, try repeatedly
      while(m#<img (width=\d+ )?src="http://# ||
            m#<a href="http://[^/]+waffleimages\.com# ||
            m#<a href="http://lpix\.org/# ||
            m#<a href="http://[^/]+photobucket\.com# ||
            m#<a href="http://[^/]*imgur\.com/# ||
            m#<a href="http://[^/]*tinypic\.com/#) {

        $lineCopy = $_;

        # Pick out the URL
        ($imgURL) = m#<img (?:width=\d+ )?src="(http://[^"]+)"#;
        if(! $imgURL) { # oh, it's a href one
          ($imgURL) = m#<a href="(http://(?:[^"]+))"#;
        }

        # Keep untouched URL for s/// later
        $origImgURL = $imgURL;

        # ImageSocket fix
        $imgURL =~ s#http://imagesocket.com/#http://content.imagesocket.com/#;
        # SALR (or similar) fix
        $imgURL =~ s/#[^#]+$//;
        # paintedover demands a forums referer
        if($imgURL =~ /paintedover/) {
          $wgetExtra = qq#--referer="http://forums.somethingawful.com/" #;
        } else {
          $wgetExtra = '';
        }
        # Un-mirror-server waffleimages links
        $imgURL =~ s#http://[^/]+.mirror.waffleimages.com/files/../([^\.]+)\..+$#http://img.waffleimages.com/$1/#;

        # Do we already have this? (standard or smiley)
        if($images{$imgURL}) {
          # Yes - just change the link to the image to the existing one
          $newImgLink = $images{$imgURL};
        } elsif($smilies{$imgURL}) {
          $newImgLink = $smilies{$imgURL};
        } elsif($imgURL =~ m#http://i.somethingawful.com/forumsystem/emoticons/#
             || $imgURL =~ m#http://i.somethingawful.com/images/#
             || $imgURL =~ m#http://fi.somethingawful.com/images/smilies/#) {
          # No, but it's a smiley
          ($smileyFile) = ($imgURL =~ m#/([^/]+)$#);

          # Do we somehow already have it?
          @haveList = grep(/$smileyFile$/, values %smilies);
          if(@haveList) {
            $errors .= "* Duplicate smiley $smileyFile at @haveList and $imgURL. Expect strange results.\n";
          }

          $newImgLink = "Images/$smileyFile";

          # Download file
          print "Fetching smiley $smileyFile ($imgURL)...";
          system(qq#wget $wgetParms -nv -o wgeterr.txt -O "$newImgLink" "$imgURL"#);

          if($? != 0) {
            print "errored\n";
            $errors .= "* wget failure getting $imgURL for smiley $smileyFile\n";
            open(ERR, "<wgeterr.txt");
            while(<ERR>) { $errors .= $_; }
            close(ERR);
          } else {
            print "ok\n";
          }

          $smilies{$imgURL} = $newImgLink;
        } else {
          # No, so make a new filename for it
          $img++;

          ($newImgLink) = ($imgURL =~ m#/([^/]+)$#);
          if($newImgLink !~ /\..{1,3}$/) { $newImgLink .= '.'; }

          # Change spaces and magic characters to _
          $newImgLink =~ s/ /_/g;
          $newImgLink =~ s/%[\dA-F]{2}/_/g;

          # Add the image number to it
          $newImgLink = "Images/$img-$newImgLink";

          # download it
          print "Fetching image $img ($imgURL)...";
          system(qq#wget $wgetExtra$wgetParms -nv -o wgeterr.txt -O "$newImgLink" "$imgURL"#);

          if($? != 0) {
            print "errored\n";
            $errors .= "* wget failure getting $imgURL for image $img\n";
            push(@errimgs, "$newImgLink");
            open(ERR, "<wgeterr.txt");
            while(<ERR>) { $errors .= $_; }
            close(ERR);
          } else {
            print "ok\n";
          }

          # and store the old/new image links in case they're used again
          $images{$imgURL} = "$newImgLink";
        }

        # Adjust the post for the new image location
        $lineCopy =~ s/\Q$origImgURL\E/$newImgLink/;

        $_ = $lineCopy;
      }

      $postBody .= $_;
    }
  }

  # Fix definitely typo filter
  $postBody =~ s/\[NOTE: I AM TOO STUPID TO SPELL THE WORD "DEFINITELY" CORRECTLY\]/definitely/g;
  for my $img (@errimgs) {
    $postBody =~ s#<img src="$img" alt="" class="img" border="0">#<missing>$img</missing>#g;
    $postBody =~ s#<a href="$img(.*?)</a>#<missing>$img</missing>#gsm;
  }
}


# Download original thread from SA forums

sub getThread {
  ($threadURL) = $_[0];
    
  print "* Fetching thread from $threadURL...\n";
    
  if($uid) {
    $cookies = qq#--header "Cookie: bbuserid=$uid; bbpassword=$pass"#;
  }
  
  system(qq#wget $wgetParms -nv -O autoFetchedThread.txt $cookies "$threadURL"#);  
}


# Automatically detect browser cookies (Windows)

sub detectWinCookies {
  print "Auto-detecting cookies...\n";

  # Check Chrome first
  # (Local Application Data\Google\Chrome\User Data\Default\Cookies)
  if($ENV{'LOCALAPPDATA'}) {
    $cPath = $ENV{'LOCALAPPDATA'} . "/Google/Chrome/User Data/Default/Cookies";
  } else { # XP, gross
    $cPath = $ENV{'USERPROFILE'} . "/Local Settings/Application Data/Google/Chrome/User Data/Default/Cookies";
  }
  if(! -f $cPath) { $noChrome = "Can't find Chrome cookies"; }
  else {
    # eval all of this in case the 'use' statements were commented out
    eval {
      $dbh = DBI->connect("dbi:SQLite:dbname=$cPath", "", "");
      if(!defined($dbh)) { $noChrome = "Couldn't open Chrome cookie database"; }
      else {
        $dbh->{PrintError} = 0; # hide warnings from corrupt cookie files
        $dbres = $dbh->selectall_hashref("SELECT name,value FROM cookies WHERE name LIKE 'bb%' AND host_key='forums.somethingawful.com'", "name");
        if($dbres) {
          $uid = $$dbres{'bbuserid'}->{'value'};
          $pass = $$dbres{'bbpassword'}->{'value'};
          if($uid && $pass) { print "  Found in Chrome cookies\n"; }
          else { $noChrome = "No SomethingAwful cookies found in Chrome cookie db"; }
        } else { $noChrome = "No SomethingAwful cookies found in Chrome cookie db"; }
        $dbh->disconnect;
      }
    };
    if($@) { $noChrome = "Couldn't open Chrome cookie database"; }
  }

  if($noChrome) {
    print "  Chrome check failed: $noChrome\n";

    # Firefox
    # (Application Data\Mozilla\Firefox\Profiles\myProfile\cookies.txt)
    $cPath = $ENV{'APPDATA'} . "/Mozilla/Firefox";
    if(! -d $cPath) { $noFF =  "Firefox not installed"; }
    elsif(! open(PROINI, "<$cPath/profiles.ini")) {
      $noFF = "Couldn't read Firefox profiles file";
    } else {
      while(<PROINI>) {
        if(/^Path=/) { ($profDir) = /^Path=(.+)$/; last; }
      }
      close(PROINI);
  
      $cPath .= "/$profDir";
      if(! -d $cPath) { $noFF = "Couldn't find a Firefox profile"; }
      else {
        if(-f "$cPath/cookies.txt") {
          if(! open(COOK, "$cPath/cookies.txt")) { $noFF = "Couldn't open Firefox cookie file"; }
          else {
            while(<COOK>) {
              if(/^forums.somethingawful.com/) {
                ($key, $value) = /^\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+(\S+)\s+(\S+)/;
                if($key eq "bbuserid") { $uid = $value; }
                if($key eq "bbpassword") { $pass = $value; }
              }
            }
            close(COOK);
      
            if(! $uid) { $noFF = "No SomethingAwful cookies found in Firefox cookies"; }
            else { print "  Found in Firefox cookies\n"; }
          }
        }
        elsif(-f "$cPath/cookies.sqlite") {
          # eval all of this in case the 'use' statements were commented out
          eval {
            # Can't actually access the database if Firefox is open, so must take a copy
            $newFile = $ENV{'TEMP'} . "/cookies.sqlite";
            copy("$cPath/cookies.sqlite", "$newFile");
    
            $dbh = DBI->connect("dbi:SQLite:dbname=$newFile", "", "");
            if(!defined($dbh)) { $noFF = "Couldn't open Firefox cookie database"; }
            else {
              $dbh->{PrintError} = 0; # hide warnings from corrupt cookie files
              $dbres = $dbh->selectall_hashref("SELECT name,value FROM moz_cookies WHERE name LIKE 'bb%' AND host='forums.somethingawful.com'", "name");
              if($dbres) {
                $uid = $$dbres{'bbuserid'}->{'value'};
                $pass = $$dbres{'bbpassword'}->{'value'};
                if($uid && $pass) { print "  Found in Firefox cookies\n"; }
                else { $noFF = "No SomethingAwful cookies found in Firefox cookie db"; }
              } else { $noFF = "No SomethingAwful cookies found in Firefox cookie db"; }
              $dbh->disconnect;
            }
          };
          if($@) { $noFF = "Couldn't open Firefox cookie database"; }
        } else { $noFF = "No Firefox cookie file found"; }
      }
    }
  }

  if($noFF) {
    print "  Firefox check failed: $noFF\n";

    # Internet Explorer
    # Can't just 'use' here because it upsets other OSs
    BEGIN {
      if($^O eq "MSWin32") {
        require Win32API::Registry;
        require Win32::Console;

        Win32API::Registry->import(qw(HKEY_CURRENT_USER KEY_READ RegCloseKey RegOpenKeyEx RegQueryValueEx));
        $winConsole = new Win32::Console();
      }
    }

    if(! RegOpenKeyEx(HKEY_CURRENT_USER, 'Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders', 0, KEY_READ, $shFKey)) {
      $noIE = "Couldn't open Shell Folders in registry";
    } elsif(! RegQueryValueEx($shFKey, "Cookies", [], [], $cValue, [])) {
      $noIE = "Couldn't open IE Cookies registry key";
    } elsif(! opendir(COOKDIR, $cValue)) {
      $noIE = "Couldn't open IE Cookies folder";
    } else {
      @saCookies = grep(/\@forums.somethingawful/, readdir(COOKDIR));
      closedir(COOKDIR);

      foreach $cFile (@saCookies) {
        if(open(COOK, "<$cValue/$cFile")) {
          while(<COOK>) {
            chomp($key = $_);
            chomp($value = <COOK>);
            $site = <COOK>; for($i=0;$i<6;$i++) { $junk = <COOK>; }

            if($key eq "bbuserid") { $uid = $value; }
            if($key eq "bbpassword") { $pass = $value; }
          }
          close(COOK);
        }

        # Stop checking cookie files if we got a result
        last if($uid);
      }
      RegCloseKey($shFKey);

      if(! $uid) { $noIE = "No SomethingAwful cookies found in IE cookies"; }
            else { print "  Found in IE cookies\n"; }
    }
  }

  if($noIE) {
    print "  Internet Explorer check failed: $noIE\n";

    use Fcntl 'O_RDONLY', 'SEEK_CUR';
    $MSB = 0x80;
    $cPath = $ENV{'APPDATA'} . "/Opera/Opera";
    if(! -d $cPath) { $noOp = "Opera not installed?\n"; }
    else {
      if(-f "$cPath/cookies4.dat") { # location differs between versions
        ($uid, $pass) = &doOpera("$cPath/cookies4.dat");
      } else {
        ($uid, $pass) = &doOpera("$cPath/profile/cookies4.dat");
      }
      if(! $uid) { $noOp = "No SomethingAwful cookies found in Opera cookies"; }
      else { print "  Found in Opera cookies\n"; } 
    }
  }

  if($noOp) {
    print "  Opera check failed: $noOp\n\n";
    return ("", "");
  } else {
    return ($uid, $pass);
  }
}

# Automatically detect browser cookies (Mac OS X)

sub detectMacCookies {
  print "Auto-detecting cookies...\n";

  # Check Firefox first
  # $HOME/Library/Application Support/Firefox/Profiles/myProfile/cookies.txt)
  $cPath = $ENV{'HOME'} . "/Library/Application Support/Firefox";
  if(! -d $cPath) { $noFF =  "Firefox not installed"; }
  elsif(! open(PROINI, "<$cPath/profiles.ini")) {
    $noFF = "Couldn't read Firefox profiles file";
  } else {
    while(<PROINI>) {
      if(/^Path=/) { ($profDir) = /^Path=(.+)$/; last; }
    }
    close(PROINI);

    $cPath .= "/$profDir";
    if(! -d $cPath) { $noFF = "Couldn't find a Firefox profile"; }
    elsif(! open(COOK, "$cPath/cookies.txt")) { $noFF = "Couldn't open Firefox cookie file"; }
    else {
      while(<COOK>) {
        if(/^forums.somethingawful.com/) {
          ($key, $value) = /^\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+(\S+)\s+(\S+)/;
          if($key eq "bbuserid") { $uid = $value; }
          if($key eq "bbpassword") { $pass = $value; }
        }
      }
      close(COOK);

      if(! $uid) { $noFF = "No SomethingAwful cookies found in Firefox cookies"; }
      else { print "  Found in Firefox cookies\n"; }
    }
  }

  if($noFF) {
    print "  Firefox check failed: $noFF\n";

    # Safari
    if(!open(COOK, $ENV{'HOME'} . "/Library/Cookies/Cookies.plist")) {
      $noSafari = "Couldn't open Safari cookies file";
    } else {
      while(<COOK>) {
        next unless /<dict>/;
        $dom = ""; $name = ""; $value = "";
        while(<COOK>) {
          last if m#</dict>#;
          ($key) = /<key>([^<]+)</;
          $_ = <COOK>;
          ($val) = />([^<]+)</;
          if($key eq "Domain") { $dom = $val; }
          elsif($key eq "Name") { $name = $val; }
          elsif($key eq "Value") { $value = $val; }
        }
        if($dom =~ /forums.somethingawful/) {
          if($name =~ /bbuserid/) { $uid = $val; }
          elsif($name =~ /bbpassword/) { $pass = $val; }
        }
      }
      close(COOK);
      if(! $uid) { $noSafari = "No SomethingAwful cookies found in Safari cookies"; }
      else { print "  Found in Safari cookies\n"; }
    }
  }

  if($noSafari) {
    print "  Safari check failed: $noSafari\n\n";
    return ("", "");
  } else {
    return ($uid, $pass);
  }
}


sub doOpera {
  $cF = $_[0];
  sysopen(C, "$cF", O_RDONLY);
  $fileVer = &getNum(4);
  $appVer = &getNum(4);
  $tagLen = &getNum(2);
  $lenLen = &getNum(2);

  $domParts = 0;
  undef $uid; undef $pass;

  while(1) {
    $type = &getNum($tagLen);

    if($type == 1) {
      &processDomain;
    } else {
      last;
    }
  }
  close(C);

  return ($uid, $pass);
}

sub getNum {
  $bytes = $_[0];

  if(sysread(C, $var, $bytes) == 0) {
    print "Unexpected end of file\n"; 
  }

  if($bytes == 1) {
    return ord($var);
  } elsif($bytes == 2) {
    return unpack('n', $var);
  } elsif($bytes == 4) {
    return unpack('N', $var);
  } elsif($bytes == 8) {
    $v1 = unpack('N', substr($var, 0, 4));
    $v2 = unpack('N', substr($var, 4, 4));

    # This is technically a cheat, because I'm throwing away the top 4 bytes
    # Because perl doesn't like >32bit numbers
    # It doesn't matter because it's *currently* only used for timestamps
    return $v2;
  } else {
    print "Unhandled byte size $bytes\n";
    #&end;
  }
}

sub processDomain {
  # Domain Record
  my $domName;
 
  $domPartLen = &getNum($lenLen);
  do {
    $recPart = &getNum($tagLen); $domPartLen -= $tagLen;
    if($recPart == 0x1E) {
      # Domain name
      $nameLen = &getNum($lenLen); $domPartLen -= $lenLen;
      sysread(C, $domName, $nameLen);
      #print "domain $domName\n";
      $domPartLen -= $nameLen;
      $domArray[$domParts] = $domName;
      $domParts++;
      if($domArray[0] eq "com" && $domArray[1] eq "somethingawful" && $domArray[2] =~ /^forums?$/) { $sa = 1; }
         else { $sa = 0; }
    } else {
      #print "Unhandled domain part $recPart\n"; # 0x1F, 0x21, 0x25 which nobody seems to use
    }
  } while($domPartLen);

  do {
    $next = &getNum(1);

    if($next == 5 + $MSB) {
      # Useless empty path component
    } elsif($next == 4 + $MSB) {
      # End of domain
    } else {
      # Path or Cookie (or.......?)
      if($next == 1) {
        &processDomain;
        $next = -1;
      } elsif($next == 2) {
        &processPath;
        $next = -1;
      } elsif($next == 3) {
        &processCookie;
        $next = -1;
      } else {
        print "Unhandled component type $type\n";
      }
    } 
  } while($next != 4 + $MSB); 
  #print "done domain $domName!\n";
  $domParts--;
}


sub processPath {
  $pathLen = &getNum($lenLen);

  do {
    $pathPart = &getNum($tagLen); $pathLen -= $tagLen;
    if($pathPart != 0x1D) { print "Unhandled path component $pathPart\n"; }

    # Path string
    $pathStrLen = &getNum($lenLen); $pathLen -= $lenLen;
    sysread(C, $pathStr, $pathStrLen);
    #print "Path is $pathStr\n";
    $pathLen -= $pathStrLen;
  } while($pathLen);
  #print "done path!\n";
}

sub processCookie {
  $cookieLen = &getNum($lenLen);

  do {
    $cookPart = &getNum($tagLen); $cookieLen -= $tagLen;

    # Strip any flag value
    $bool = (($cookPart & 0x80) == 0x80); 
    $cookPart = $cookPart & 0x7f;

    if($cookPart == 0x10) {
      # Cookie name
      $nameLen = &getNum($lenLen); $cookieLen -= $lenLen;
      sysread(C, $cookName, $nameLen);
      #print "Cookie named $cookName\n";
      $cookieLen -= $nameLen;
    } elsif($cookPart == 0x11) {
      # Cookie value
      $valLen = &getNum($lenLen); $cookieLen -= $lenLen;
      sysread(C, $cookValue, $valLen);
      #print "Cookie valued $cookValue\n";
      $cookieLen -= $valLen;
      if($sa && $cookName eq "bbuserid") { $uid = $cookValue; }
      if($sa && $cookName eq "bbpassword") { $pass = $cookValue; }
    } elsif($cookPart == 0x12) {
      # Cookie expiry date
      $expireLen = &getNum($lenLen); $cookieLen -= $lenLen;
      $expireTime = &getNum($expireLen); $cookieLen -= $expireLen;
      #print "Cookie expires on ", scalar(localtime($expireTime)),"\n";
    } elsif($cookPart == 0x13) {
      # Cookie last usage time
      $usedLen = &getNum($lenLen); $cookieLen -= $lenLen;
      $usedTime = &getNum($usedLen); $cookieLen -= $usedLen;
      #print "Cookie last used on ", scalar(localtime($usedTime)),"\n";
    } elsif($cookPart == 0x19) {
      # HTTPS only
    } elsif($cookPart == 0x1B) {
      #print "Cookie will be sent to ";
    } elsif($cookPart == 0x1C) {
      # Delete protection
    } elsif($cookPart == 0x20) {
      # Not sent if /pathxyz, only if /path/xyz
    } elsif($cookPart == 0x22) {
      # set by login form
    } elsif($cookPart == 0x23) {
      # set by HTTP auth login
    } elsif($cookPart == 0x24) {
      # Third-party cookie
    } elsif($cookPart == 0x27) {
      # Mystery new Opera 9.50 flag
    } else {
      #print "Unexpected cookie type $cookPart\n"; exit;
    }
  } while($cookieLen);
  #print "done cookie!\n";
}
__END__

Pre-github Revision History

2011/02/05 - Added closing </td> and </tr> tags in video table

2011/01/17 - [baldurk] add <missing>...</missing> tags around missing images
                       removed s#<br />#<br>#g
              
2010/11/22 - Modified HTML generation for new LP archive layout

2010/09/25 - <dt class="author"> is now <dt class="author" title="">

2008/12/01 - Removed fromearth.net reference from $cssURL

2008/09/23 - Added Viddler as a potential video source
             Pass forums referer to paintedover to get full-size image
             forumimages.somethingawful.com is now fi.somethingawful.com

2008/04/01 - Smileys are now stored along with the LP

2008/03/28 - Removed all code relating to archives.somethingawful.com
             Added blip.tv as an 'other' video site, removed stage6

2008/02/20 - Changed 'Date Collected' to 'Date Added'

2008/02/04 - Added code to make wget work more automatically on Mac OS X

2008/01/03 - Disable $downloadVideos by default

2007/12/31 - Strip trailing #..... stuff from images (eg #via=salr)

2007/12/23 - Line endings in output files will now be fixed to match the
             downloader's OS

2007/12/13 - Retry fetching any failed videos at the end of the script

2007/12/11 - Create stats.txt file with the total video size and any
             errors generated during the fetch

2007/12/05 - Automatically replace spaces and %xx characters in filenames
             with _s

2007/11/26 - Add ' | <first link title>' to video title in first column

2007/11/23 - Video links are renamed to the name of the video site
             for multiBackups

2007/11/20 - Support for multiple video mirrors on a single line
             Replaced downloadFiles and imagesOnly with downloadVideos

2007/11/17 - Selected smilies are replaced last

2007/11/14 - Added imagesOnly option

2007/11/12 - Added variable for extra parameters to wget, starting with
             setting the max download retries to 3

2007/11/10 - Various features copied over from fetch-thread:
             downloadFiles, keeping original image filenames,
             external smiley list, reporting fetch time

2007/11/08 - Last Post date is always '?'

2007/11/05 - Date Collected is auto-filled with today's date

2007/10/27 - Handle <img width=X src="http://.... for image URLs (used
             in thumbnails)

2007/10/26 - Handle image-only links to videos

2007/10/25 - Video files are now called videoX, not X.flv

2007/10/22 - Handle multiple URLs on the same line

2007/10/21 - Skip fetching existing videos, except re-fetch the last
             existing video before fetching the next new one

2007/10/19 - Added 'Collected By' field

2007/10/18 - More recent versions of wget support 303 redirects. Changed to
             expect that.
             Only get first page of thread.

2007/10/16 - Added automatic cookie detection for Windows Firefox and IE

2007/10/13 - Merged get-source in, using a URL as a parameter to the
             script will fetch that as a forums thread

2007/10/12 - Avoid getting duplicate hrefs
             YouTube video support

2007/10/11 - Download FLV files for video.google and Dailymotion

2007/10/09 - Ignore quoted hrefs [this fix removed 2007/10/24]

2007/10/08 - wget errors now list the image number as well as the update
             number

2007/10/07 - Created initial version - fetches first post with images,
             catches <a hrefs and generates a table for them

__END__

Revision History

2009/02/18 - Removed all video-downloading code, tidied up table-creation
             (somewhat), added some iffy Opera-cookies code

2009/02/06 - Fixed the de-mirror-servering

2008/12/31 - De-mirror-server waffleimages links

2008/12/01 - Removed fromearth.net reference from $cssURL

2008/09/23 - Added Viddler as a potential video source
             Pass forums referer to paintedover to get full-size image
             forumimages.somethingawful.com is now fi.somethingawful.com

2008/04/01 - Smileys are now stored along with the LP

2008/03/28 - Removed all code relating to archives.somethingawful.com
             Added blip.tv as an 'other' video site, removed stage6

2008/02/20 - Changed 'Date Collected' to 'Date Added'

2008/02/04 - Added code to make wget work more automatically on Mac OS X

2008/01/03 - Disable $downloadVideos by default

2007/12/31 - Strip trailing #..... stuff from images (eg #via=salr)

2007/12/23 - Line endings in output files will now be fixed to match the
             downloader's OS

2007/12/13 - Retry fetching any failed videos at the end of the script

2007/12/11 - Create stats.txt file with the total video size and any
             errors generated during the fetch

2007/12/05 - Automatically replace spaces and %xx characters in filenames
             with _s

2007/11/26 - Add ' | <first link title>' to video title in first column

2007/11/23 - Video links are renamed to the name of the video site
             for multiBackups

2007/11/20 - Support for multiple video mirrors on a single line
             Replaced downloadFiles and imagesOnly with downloadVideos

2007/11/17 - Selected smilies are replaced last

2007/11/14 - Added imagesOnly option

2007/11/12 - Added variable for extra parameters to wget, starting with
             setting the max download retries to 3

2007/11/10 - Various features copied over from fetch-thread:
             downloadFiles, keeping original image filenames,
             external smiley list, reporting fetch time

2007/11/08 - Last Post date is always '?'

2007/11/05 - Date Collected is auto-filled with today's date

2007/10/27 - Handle <img width=X src="http://.... for image URLs (used
             in thumbnails)

2007/10/26 - Handle image-only links to videos

2007/10/25 - Video files are now called videoX, not X.flv

2007/10/22 - Handle multiple URLs on the same line

2007/10/21 - Skip fetching existing videos, except re-fetch the last
             existing video before fetching the next new one

2007/10/19 - Added 'Collected By' field

2007/10/18 - More recent versions of wget support 303 redirects. Changed to
             expect that.
             Only get first page of thread.

2007/10/16 - Added automatic cookie detection for Windows Firefox and IE

2007/10/13 - Merged get-source in, using a URL as a parameter to the
             script will fetch that as a forums thread

2007/10/12 - Avoid getting duplicate hrefs
             YouTube video support

2007/10/11 - Download FLV files for video.google and Dailymotion

2007/10/09 - Ignore quoted hrefs [this fix removed 2007/10/24]

2007/10/08 - wget errors now list the image number as well as the update
             number

2007/10/07 - Created initial version - fetches first post with images,
             catches <a hrefs and generates a table for them

