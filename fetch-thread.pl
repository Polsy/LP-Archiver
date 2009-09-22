#!/usr/bin/perl

# Thread URL, if not already fetched into a file
$threadURL = "";

# Name the the game here - used as the main heading on the index page
# and the page title of updates
# This will also be automatically applied when renumbering a thread
$gameName = "?";

# Your SA name, for the 'Collected By' line
$collector = "Your SA Name Here";


# These following settings should be set to 1 to enable them,
# or to 0 to disable them

# Fetch images and videos
# (you might want to temporarily disable this for faster testing)
$downloadFiles = 1;

# Fetch videos (for hybrid LPs)
$downloadVideos = 0;

# Use automatic chapter naming - names chapters by picking up the first
# bold-texted line of a post, or the first line matching one of the words
# in chapterWords list below)
$autoChapters = 1;


# You're unlikely to need to change the following settings:

# Minimum number of images (excluding emoticons) to make a post count
# as a valid update (otherwise it will be skipped)
$minImages = 2;

# Only use posts made by the thread author
$authorPosts = 1;

# Accept posts even if they have no images, as long as they have links
# to videos (<a href=... to a known video site) (can be useful for hybrid LPs)
$videoPosts = 0;

# Threshold above which automatic chapter naming will be used. Expressed
# as a percentage of posts where an automatic chapter name was found against
# the total number of chapters found in the thread.
$autoChapThresh = 75;

# Optional parameters specific to wget
# - Retry downloading files up to a maximum of 3 times
$wgetParms = "--tries=3";

# List of words that, if matched on a line, become the chapter title
@chapterWords = ('Chapter ', 'Update ', 'Episode ');

# List of sites that contain videos (so any hrefs referring to these
# sites are most likely videos)
@videoSites = ('dailymotion.com', 'youtube.com', 'video.google.[^/]+');

# Other sites containing videos (to mark a post as containing content,
# but not actually downloading the videoe/making a Backup link)
@otherVidSites = ('filefront.com', 'vimeo.com', 'blip.tv');

# Location of CSS file
$cssURL = "/LetsPlay/myStyle.css";

# Black hole file for checking a file exists on the server
$nullFile = "/dev/null";


# renum'ing? - ie, does index.html exist?
if(-s "index.html") {
  &renumThread;
  exit;
}

# Ok, we're fetching

# OS and cookie detection
# - Auto-detects by default
#   Windows: Firefox, IE     Mac OS X: Firefox, Safari
if($^O eq "MSWin32") {
  $isWin32 = 1;
  $nullFile = "NUL";
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
    if(-s "showthread.txt") {
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

# Pre-count the number of posts in the file
$postCount = 0;
while(<IN>) {
  if(/<!-- EndContentMarker --/) { $postCount++; }
}

# And return to the start of the file
seek(IN, 0, SEEK_SET);

$upd = 0; $post = 0; $gotUpdate = 0;
$authorName = "?"; $currAuthor = "?";
$firstDate = "?"; $lastDate = "?";
$threadName = "?"; $threadURL = "?";
$numPics = 0; $totSize = 0; 
$numVids = 0; $vidSize = 0;
$errors = ""; $skippedImgFile = ""; $skippedVidFile = "";


if($autoChapters) {
  # Start by running through to check how many valid posts have 
  # automatically-recognised chapter titles
  $chapTitleChecking = 1; $useAutoChapters = 1;
  $chapTitlesGot = 0;

  # Only interested in posts rather than stats/info here
  # Still need to catch the author for authorPosts check
  while(<IN>) {
    # Found a post
    if(/<!-- BeginContentMarker -->/) {
      # Skip it if authorPosts is on and it's not by the thread author
      unless($authorPosts && ($currAuthor ne $authorName)) {
        &getPost;
      }
    }
    elsif(/<dt class="author/) { # Store author for this post
      ($currAuthor) = m#<dt class="author(?: op)?">(.+)</dt>#;

      if($authorName eq "?" && $currAuthor) { # Store thread author (first author found)
        $authorName = $currAuthor;
      }
    }
  }
}

# Catch empty thread download
if($upd == 0 && $autoChapters) {
  print "\nNo posts found in thread. Possibly your SA browser cookies were not found (see above), you don't have archives access (if applicable), or there is a temporary server error.\n";
  print "\nThe contents of autoFetchedThread.txt may be useful.\n";

  # Wait before exiting
  print "\nPress enter to finish\n";
  $junk = <STDIN>;
  exit;
}

# Set automatic chapter naming to off
$useAutoChapters = 0;
# unless the percentage is met
if($autoChapters && ($chapTitlesGot / $upd) >= ($autoChapThresh / 100)) {
  $useAutoChapters = 1;
}

# Back to the start again
seek(IN, 0, SEEK_SET);
# Reset things
$chapTitleChecking = 0;
$upd = 0; $post = 0;
$currAuthor = "?"; $authorName = "?";

# Go through the file until you hit a post, useful thing or the file ends
while(<IN>) {
  # Found a post
  if(/<!-- BeginContentMarker -->/) {
    # Skip it if authorPosts is on and it's not by the thread author
    unless($authorPosts && ($currAuthor ne $authorName)) {
      &getPost;
    } else {
      # Just increase the post count
      $post++;
    }
  }
  
  elsif(/<dt class="author/) { # Store author for this post
    ($currAuthor) = m#<dt class="author(?: op)?">(.+)</dt>#;

    if($authorName eq "?" && $currAuthor) { # Store thread author (first author found)
      $authorName = $currAuthor;
    }
  }

  # $gotUpdate is only set if the last post retrieved was
  # a valid content-containing one (ie, one with images)
  elsif(/<td class="postdate">/ && $gotUpdate) { # First/last post date
    $junk = <IN>; # blank line
    $junk = <IN>; # post number
    $junk = <IN>; # thread/user numbers
    $_ = <IN>; # actual date info
    ($lastDate) = m#(\w+ \d+, \d+) \d+:\d+#; 

    if($firstDate eq "?") { $firstDate = $lastDate; }

    # Tack the date onto the update file in case of renumbering
    open(OUT, ">>Update $updDir/index.html");
    print OUT "<!-- date $lastDate -->\n";
    close(OUT);

    $gotUpdate = 0;
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

# Need to delete the 'next' links from the final update

# Read in the existing file
open(IN, "<Update $updDir/index.html");
@lines = <IN>;
close(IN);

# And write it straight back out, minus the offending lines
$checking = 0;
open(OUT, ">Update $updDir/index.html");
for $l (@lines) {
  if($checking) {
    next if $l =~ /Next Chapter/;
  }

  print OUT $l;

  if($l =~ /<!-- begin (header|footer) -->/) {
    $checking = 1;
  } elsif($l =~ /<!-- end (header|footer) -->/) {
    $checking = 0;
  }
}
close(OUT);

# Fetch smilies (should be virtually guaranteed)
if(%smilies) {
  mkdir "Smilies";

  for $smileyURL (keys %smilies) {
    $smileyFile = $smilies{$smileyURL};
    # Strip the "../Smilies/" from the filename
    $smileyFile =~ s#^.+/##;
    
    print "Fetching smiley $smileyFile ($smileyURL)...";
    if($downloadFiles) {
      system(qq#wget $wgetParms -nv -o wgeterr.txt -O "Smilies/$smileyFile" "$smileyURL"#);
    } else {
      $? = 0; # fake success
    }

    if($? != 0) {
      print "failed\n";
      $errors .= "* failed download of $smileyFile ($smileyURL)\n";
      open(ERR, "<wgeterr.txt");
      while(<ERR>) { $errors .= $_; }
      close(ERR);
    } else {
      print "ok\n";
    }
  }
}

# Retry fetching any images that failed previously
for $fImg (@failedImgs) {
  ($failFile, $failURL, $failText) = @$fImg; 

  print "Retrying: $failText ($failURL)...";
  if($downloadFiles) {
    system(qq#wget $wgetParms -nv -o wgeterr.txt -O "$failFile" "$failURL"#);
  } else {
    $? = 0; # fake success
  }

  if($? != 0) {
    print "failed\n";
    $errors .= "* failed download of $failFile ($failURL), even after retrying\n";
    open(ERR, "<wgeterr.txt");
    while(<ERR>) { $errors .= $_; }
    close(ERR);
  } else {
    print "ok\n";
    $errors .= "* succeeded in retrying download of $failFile ($failURL)\n";
  }

  # update statistics (regardless of failure)
  $numPics++;
  $totSize += (-s "$failFile");
}
# Remove wget error file (if it was generated, either here or earlier)
unlink 'wgeterr.txt';

# Get the current date to use as the Date Added
use POSIX;
$addedDate = POSIX::strftime("%b %d, %Y", localtime(time));

# Create the index
open(IDX, ">index.html") || die "Couldn't create index: $!\n";

print IDX <<HEADER1;
<html>

<head>
<link rel="StyleSheet" href="$cssURL" type="text/css">
<TITLE>$gameName - Index</TITLE>
</head>

<body>
<h1>Let's Play $gameName</h1>
Author: $authorName<br>
Collected By: $collector<br>
Original Thread: <A HREF="$threadURL">$threadName</A><br>
First Update: $firstDate<br>
Last Update: $lastDate<br>
Date Added: $addedDate<br>

<br><br><br>
<h1>Statistics</h1>
Number of Pictures: $numPics<br>
HEADER1

if(! $upd) {
  print IDX "No updates found!\n";
  $errors .= "No posts were found\n";
} else {
  printf IDX "Total Size: %2.2f MB<br>\n", ($totSize / 1048576);
  print IDX "Number of Updates: $upd<br>\n";
  printf IDX "Pictures per Update: %2.2f<br>\n", ($numPics / $upd);
  printf IDX "Size per Update: %2.2f MB<br>\n", ($totSize / $upd / 1048576);
}

print IDX <<HEADER2;

<br><br><br>
<h1>Table of Contents</h1>
<!-- begin TOC -->
HEADER2

for($i=1; $i<=$upd; $i++) {
  print IDX qq#<li><A HREF="Update%20# . sprintf("%02d", $i) . qq#/index.html">$chapTitles[$i]</A><br>\n#;
}

print IDX <<FOOTER;
<!-- end TOC -->

<br><br><br>
<A HREF="/LetsPlay/">Back to Let's Play Index</A>
</body>
</html>
FOOTER

close(IDX);

#print "\nPer-post statistics:\n";
if(scalar(@videoURLs)) {
  print "\nVideos downloaded:\n";
  open(V, ">stats.txt");
  $vNum = 1;
  for($i=0; $i<=$#postStats; $i++) {
    ($img, $vid) = @{$postStats[$i]};
    #if($vid) { print "V "; } else { print "  "; }
    #printf "%3d: %3d images, %2d videos\n", $i+1, $img, $vid
    if($vid) {
      if($vid == 1) {
        $txt = sprintf "%10s:  video %d\n", "Update " . ($i+1), $vNum;
      } else {
        $txt = sprintf "%10s: videos %d-%d\n", "Update " . ($i+1), $vNum, $vNum+$vid-1;
      }
      print $txt; print V $txt;
      $vNum += $vid;
    }
  }
  $txt = "- Total videos: " . scalar(@videoURLs) . "\n";
  print $txt; print V $txt;
  $txt = sprintf "- Total video size: %2.2f MB\n", ($vidSize / 1048576);
  print $txt; print V $txt;
  close(V);
} else {
  unlink "stats.txt";
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

if($isWin32) {
  $winConsole->Title("Finished - $gameName");
}

# Wait before exiting
print "\nPress enter to finish\n";
$junk = <STDIN>;


# Subroutines

# Extract an entire post from a thread list, save the images

sub getPost {
  $post++;
  $img = 0; $vidStart = $numVids; $vidEnd = $vidStart;
  $keepPost = 0; $quoting = 0;
  $chapTitle = "";
  undef %images; undef @newVids;

  $postBody = "";

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

    # Start/end a quote?
    if(m#<blockquote #) {
      $quoting = 1;
    } elsif(m#</blockquote>#) {
      $quoting = 0;
    }

    # Chapter title? (first bolded item in post, or matched word)
    if(! $quoting && $useAutoChapters && ! $chapTitle) {
      $isTitle = 0;
      if(m#<b># && m#</b>#) {
        ($chapTitle) = m#<b>(.+)$#;
        $isTitle = 1;
      } else {
        # Match word?
        for $word (@chapterWords) {
          if(/$word/) { $isTitle = 1; $chapTitle = $_; }
        }
      }

      if($isTitle) {
        # Remove any other tags
        $chapTitle =~ s#</?[^>]+>##g;
        # Remove line ending character
        chomp;
      }
    }

    # Check for HREFs to videos
    if(m#<a href=#) {
      do { # keep going until we get a valid video or run out of links
        ($URL, $title) = m#<a href="(http://[^"]+)"[^>]*>([^<]+)</a>#;
        if(! $title) { # Can happen with image-only video links
          ($URL) = m#<a href="(http://[^"]+)"[^>]*>.+</a>#;
          $title = "(no title)";
        }

        # Video?
        $isVideo = 0;
        for $site (@videoSites) {
          if($URL =~ /$site/) { $isVideo = 1; }
        }
        if(! $isVideo) {
          for $site (@otherVidSites) {
            if($URL =~ /$site/) { $isVideo = 2; }
          }
        }

        if($isVideo == 1) {
          # Avoid duplicate videos
          $vidNumber = 0;
          for($i=0; $i<=$#videoURLs; $i++) {
            if($videoURLs[$i] eq $URL) { $vidNumber = $i+1; }
          }

          # If we don't already have it, add it to the potential new video
          # list (discarded if the post is not kept)
          if(! $vidNumber) {
            push(@newVids, $URL);
            $vidEnd++;
            $vidNumber = $vidEnd;
          } # else vidNumber is already the number of the existing video

          # Add a 'backup' link
          unless(! $downloadFiles || ! $downloadVideos) {
            s#(<a href[^<]+</a>)#$1 / <a href="../Videos/video$vidNumber.AVI" target="_blank" rel="nofollow">Backup</a>#;
          }
        }

        if($isVideo) { # Do this even if it's not a downloadable video
          if(! $quoting && $videoPosts) { $keepPost = 1; }
        }

        # Skip reprocessing this link
        s#<a href#<x href#;
      } while(m#<a href# && ! $isVideo);

      # Restore links
      s#<x href#<a href#g;
    }

    # Catch images

    # loop in case there's multiple images on one line, try repeatedly
    while(m#<img (width=\d+ )?src="http://# ||
          m#<a href="http://[^/]+waffleimages\.com#) {

      # Pick out the URL
      ($imgURL) = m#<img (?:width=\d+ )?src="(http://[^"]+)"#;
      if(! $imgURL) { # oh, it's a href one
        ($imgURL) = m#<a href="(http://[^"]+)"#;
      }

      # Keep untouched URL for s/// later
      $origImgURL = $imgURL;

      # ImageSocket fix
      $imgURL =~ s#http://imagesocket.com/#http://content.imagesocket.com/#;
      # SALR (or similar) fix
      $imgURL =~ s/#[^#]+$//;
      # Un-mirror-server waffleimages links
      $imgURL =~ s#http://[^/]+.mirror.waffleimages.com/files/../([^\.]+)\.(.+)$#http://img.waffleimages.com/$1/waffle.$2#;

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

        $newImgLink = "../Smilies/$smileyFile";
        $smilies{$imgURL} = $newImgLink;
      } else {
        # No, so get a filename for it
        $img++;

        ($newImgLink) = ($imgURL =~ m#/([^/]+)$#);
        if($newImgLink !~ /\..{1,3}$/) { $newImgLink .= '.'; }

        # Change spaces and magic characters to _
        $newImgLink =~ s/ /_/g;
        $newImgLink =~ s/%[\dA-F]{2}/_/g;

        # Add the image number to it
        $newImgLink = "$img-$newImgLink";

        # and store the old/new image links in case they're used again
        $images{$imgURL} = "$newImgLink";

        if((! $quoting) && ($img >= $minImages)) { $keepPost = 1; }
      }

      # Adjust the post for the new image location
      s/\Q$origImgURL\E/$newImgLink/;
    }

    $postBody .= $_;
  }

  if($chapTitleChecking) {
    if($keepPost) {
      $upd++;
      if($chapTitle) { $chapTitlesGot++; }
      $keepPost = 0;
    }
  } else { 
    # Accept the OP as a valid post regardless of any restrictions
    # (unless we're chapter-checking)
    if($upd == 0) { $keepPost = 1; }
  }

  if(! $keepPost) {
    # Keeping requires: $minImage images or a video href (if videoPosts is on)
    # not contained inside a [quote] (a <blockquote>)
    if(! $chapTitleChecking) {
      print "*** Skipping non-content post (would have been chapter ",$upd+1,")\n";
    }
  } else {
    # This post was valid, so accept post date immediately below it
    $gotUpdate = 1;
    $upd++; $updDir = sprintf("%02d", $upd);

    # Fix definitely typo filter
    $postBody =~ s/\[NOTE: I AM TOO STUPID TO SPELL THE WORD "DEFINITELY" CORRECTLY\]/definitely/g;
    # Switch <br /> for <br>
    $postBody =~ s#<br />#<br>#g;

    # Create a title if one wasn't found in the post
    if(! $chapTitle) { $chapTitle = "Chapter $upd"; }
    # store it
    $chapTitles[$upd] = $chapTitle;

    # Create a directory to put it all in
    mkdir "Update $updDir" || die $!; 

    # Generate the HTML file
    open(OUT, ">Update $updDir/index.html") || die $!;

    print OUT <<HEADER;
<html>

<head>
<link rel="StyleSheet" href="$cssURL" type="text/css">
<TITLE>$gameName - $chapTitle</TITLE>
</head>

<body>
<br><br><br>
HEADER

    # Next/previous links container
    print OUT "<!-- begin header -->\n";
    &addHdrFtr;
    print OUT "<!-- end header -->\n\n";
    print OUT "<br><br><br>\n";

    # Main content
    print OUT $postBody;

    # and footer
    print OUT "<br><br><br>\n\n";
    print OUT "<!-- begin footer -->\n";
    &addHdrFtr;
    print OUT "<!-- end footer -->\n";
    print OUT "</body>\n";
    print OUT "</html>\n";
    close(OUT);

    # Download images
    $iNum = 0; $iCount = keys %images;
    foreach $imgURL (sort { $images{$a} <=> $images{$b} } keys %images) {
      $iNum++;
      $imgFile = "Update $updDir/$images{$imgURL}";

      # Skip already-downloaded files
      if(-s $imgFile) {
        print "Skipping image $imgFile ($imgURL), already exists\n";
        $skippedImgFile = $imgFile;
        $skippedImgURL = $imgURL;

        # still need to update stats
        $numPics++;
        $totSize += (-s "$imgFile");

        next; # continue with for loop
      } elsif($skippedImgFile) {
        # undo the stat change for this first
        $numPics--; # I could avoid this one, but it's staying for clarity
        $totSize -= (-s "$skippedImgFile");

        # fix for paintedover
        if($imgURL =~ /paintedover/) {
          $wgetExtra = qq#--referer="http://forums.somethingawful.com/" #;
        } else {
          $wgetExtra = '';
        }

        # re-get the last skipped one before continuing with the new files
        print "Re-getting last existing image ($skippedImgURL)...";
        if($downloadFiles) {
          system(qq#wget $wgetExtra$wgetParms -nv -o wgeterr.txt -O "$skippedImgFile" "$skippedImgURL"#);
        } else {
          $? = 0; # fake success
        }

        if($? != 0) {
          print "failed\n";
          # Store for retrying later
          push(@failedImgs, [$skippedImgFile, $skippedImgURL, "regetting last existing image"]);
        } else {
          print "ok\n";

          # update statistics
          $numPics++;
          $totSize += (-s "$skippedImgFile");
        }

        $skippedImgFile = "";
      }

      # download it
      print "Fetching image $iNum/$iCount ($imgURL) for post $post / $postCount...";

      if($isWin32) {
        # set title bar to indicate progress
        $winConsole->Title("Post $post / $postCount : image $iNum - $gameName");
      }

      # paintedover demands a forums referer
      if($imgURL =~ /paintedover/) {
        $wgetExtra = qq#--referer="http://forums.somethingawful.com/" #;
      } else {
        $wgetExtra = '';
      }

      if($downloadFiles) {
        system(qq#wget $wgetExtra$wgetParms -nv -o wgeterr.txt -O "$imgFile" "$imgURL"#);
      } else {
        $? = 0; # fake success
      }

      if($? != 0) {
        print "failed\n";
        push(@failedImgs, [$imgFile, $imgURL, "image $iNum in update $upd"]);
      } else {
        print "ok\n";

        # update statistics
        $numPics++;
        $totSize += (-s "$imgFile");
      }
    }

    # and accept the URLs into the video list
    if(defined(@newVids)) {
      push(@videoURLs, @newVids);

      # Download FLVs

      # Make a directory for them (which does nothing if it already exists)
      mkdir "Videos";
      
      for($vid=$vidStart; $vid<$vidEnd; $vid++) {
        $numVids++;

        # Skip already-downloaded files
        if(-s "Videos/video$numVids") {
          print "Skipping video Videos/video$numVids ($videoURLs[$vid]), already exists\n";
          $skippedVidFile = "Videos/video$numVids";
          $skippedVidURL = $videoURLs[$vid];

          # Update videos size
          $vidSize += (-s "Videos/video$numVids");
          next; # continue with for loop
        } elsif($skippedVidFile) {
          # re-get the last skipped one before continuing with the new files
          print "Re-getting last existing video ($skippedVidURL)...\n";
          # 'Remove' size first
          $vidSize -= (-s "$skippedVidFile");

          $success = &downloadVid($skippedVidURL, $skippedVidFile);
          if(! $success) {
            print "failed\n";
            $errors .= "* failed to redownload pre-existing video $skippedVidFile ($skippedVidURL)\n";
          } else {
            print "...ok\n";
          }

          # Add size back
          $vidSize += (-s "$skippedVidFile");
          $skippedVidFile = "";
        }

        print "Trying to download video $numVids ($videoURLs[$vid])...\n";
        $success = &downloadVid($videoURLs[$vid], "Videos/video$numVids");  
        if(! $success) {
          print "failed\n";
          $errors .= "* failed to download video $numVids for update $upd ($videoURLs[$vid])\n";
        } else {
          print "...ok\n";
          $vidSize += (-s "Videos/video$numVids");
        }
      }
    }

    # Store per-post stats
    push(@postStats, [$img, $vidEnd-$vidStart]);
  }
}


# Add header/footer text to chapter pages (next chapter, previous chapter,
# return to index)

sub addHdrFtr {
  if($upd > 1) {
    print OUT qq#<A HREF="../Update%20# . (sprintf("%02d",$upd-1)) . qq#/index.html"><< Previous Chapter</A><br>\n#;
  }
  print OUT qq#<A HREF="../Update%20# . (sprintf("%02d",$upd+1)) . qq#/index.html">>> Next Chapter</A><br>\n#;
  print OUT qq#<A HREF="../index.html">^^ Index</A><br>\n#;
}


# Download FLV files from video sites

sub downloadVid {
  ($vidURL, $vidFile) = @_;

  # If not fetching, fake success
  if(! $downloadFiles) { return 1; }
  if(! $downloadVideos) { return 1; }

  # fix URL for possible youtube issue
  $vidURL =~ s#youtube.com/\?#youtube.com/watch\?#;

  system(qq#wget $wgetParms -q -O tmpvid.txt "$vidURL"#);
  if($? != 0) {
    print "couldn't download original URL...";
    unlink 'tmpvid.txt';
    return 0;
  }

  $ok = 0;
  if($vidURL =~ /video.google/) { # Google Video
    open(I, "<tmpvid.txt") || die $!;
    while(<I>) {
      next unless /<noscript>/;

      ($flvURL) = m# src="([^"]+)" #;
      if($flvURL) {
        $ok = 1;
        $flvURL =~ s#^/googleplayer.swf\?&videoUrl=##;

        # URL-decode URL (from 'man perlfaq9')
        $flvURL =~ s/%([A-Fa-f\d]{2})/chr hex $1/eg; 
        last;
      }
    }
    close(I);

  } elsif($vidURL =~ /dailymotion.com/) { # Dailymotion
    $var = "";

    open(I, "<tmpvid.txt") || die $!;
    while(<I>) {
      next unless /= new SWFObject/;
      ($var) = /^var (.+) = new SWFObject/;
      last;
    }

    if($var) {
      while(<I>) {
        next unless /$var.addVariable\("url",/;
        ($flvURL) = /"url", "([^"]+)"/;
        last;
      }
    }
    close(I);

    if($flvURL) {
      $flvURL =~ s/%([A-Fa-f\d]{2})/chr hex $1/eg; 
      $ok = 1;
    }

  } elsif($vidURL =~ /youtube/) {
    $part1 = ""; $part2 = "";
    open(I, "<tmpvid.txt") || die $!;
  
    while(<I>) {
      next unless /var swfArgs = /;
      ($part1, $part2) = /, "video_id": "([^"]+)", .+, "t": "([^"]+)",/;
      last;
    }
    close(I);
  
    if($part1) {
      $flvURL = "http://youtube.com/get_video?video_id=$part1&t=$part2";
      $ok = 1;
    } 

  } else { # Other video site currently not handled
    $ok = 0;
  }

  unlink 'tmpvid.txt';

  if(! $ok) {
    return 0;
  } else {
    system(qq#wget $wgetParms -O "$vidFile" "$flvURL"#);
    if($? == 0) { return 1; }
           else { return 0; }
  }
}


# Download original thread from SA forums

sub getThread {
  ($threadURL) = $_[0];

  print "* Fetching thread from $threadURL...\n";

  if($uid) {
    $cookies = qq#--header "Cookie: bbuserid=$uid; bbpassword=$pass"#;
  }

  open(FIRST, qq#wget $wgetParms -nv -O - $cookies "$threadURL" |#);
  open(OUT, ">autoFetchedThread.txt") || die "Couldn't write temporary thread file: $!";

  $pages = 1;
  while(<FIRST>) {
    if(/<div class="pages top"/) {
      ($pages) = />Pages \((\d+)\): /;
    }
    print OUT ;
  }
  close(FIRST);

  if($pages > 1) {
    print "\n* $pages pages to fetch\n";

    for($i=2; $i<=$pages; $i++) {
      open(PAGE, qq#wget $wgetParms -nv -O - $cookies "${threadURL}&pagenumber=$i" |#);
      while(<PAGE>) { print OUT ; }
      close(PAGE);
    }
  }
  close(OUT);
}


# Automatically detect browser cookies (Windows)

sub detectWinCookies {
  print "Auto-detecting cookies...\n";

  # Check Firefox first
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
    print "  Internet Explorer check failed: $noIE\n\n";
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

###
### renum-thread
###

sub renumThread {
  # Pick up the directory's subdirectories
  opendir(DIRH, ".");
  @dirContent = grep(-d, readdir(DIRH));
  close(DIRH);

  # Go through each one, find the highest-numbered update
  $lastUpdate = 0;

  foreach $d (@dirContent) {
    ($updNum) = ($d =~ /^Update (\d+)$/);
    if($updNum > $lastUpdate) { $lastUpdate = $updNum; }
  }

  # Keep track of how many updates are missing so far
  $subtract = 0;

  # Keep stats for the new index page
  $firstDate = "?"; $lastDate = "?";
  $numPics = 0; $totSize = 0;
  $idxTOC = "";

  # Import existing stats
  $oldErrors = "";
  @oldVidStats = ();

  if(open(V, "<stats.txt")) {
    $errs = 0;
    while(<V>) {
      if($errs) {
        $oldErrors .= $_;
      }
      elsif(/Errors:/) {
        $errs = 1;
      } else {
        ($upNum) = /Update (\d+):/;
        if($upNum) {
          $oldVidStats[$upNum] = $_;
        }
      }
    }
    close(V);
  }

  # Prepare to regenerate stats file
  open(V, ">stats.txt");
  $numVids = 0; $vidSize = 0;
  $rmvVid = "";

  # Auto-renumber any Update X.4s (that are directories) - an 'insert'
  # Will need to trigger a rewrite of next/previous links
  $inserted = 99999;

  @fours = glob(sprintf("Update\\ *.4")); 
  foreach $four (@fours) {
    ($n) = ($four =~ /Update (\d+)\.4/);

    # Move everything above it up one (starting from the high end)
    for($upd=$lastUpdate; $upd>$n; $upd--) {
      rename "Update " . (sprintf("%02d", $upd)), "Update " . (sprintf("%02d", $upd+1));
    } 

    # and the last update is now one higher
    $lastUpdate++;

    # so now there's space to give the inserted one a proper number
    rename $four, "Update " . (sprintf("%02d", $n+1));  
    print "Renumbered $four to Update ", $n+1, "\n";

    if($inserted > $four) { $inserted = $four; }
  }

  # Check each update exists, fix the next and/or previous links
  for($upd=1; $upd<=$lastUpdate; $upd++) {
    if(-d "Update " . sprintf("%02d", $upd)) { # it still exists

      # Read in the existing index file
      open(IN, "<Update " . sprintf("%02d", $upd). "/index.html");
      @lines = <IN>;
      close(IN);

      # Pick up the existing post date from the file (if it's there)
      if($lines[-1] =~ /<!-- date/) {
        ($lastDate) = ($lines[-1] =~ /<!-- date (.+) -->/);
        if($firstDate eq "?") { $firstDate = $lastDate; }
      }

      # Pick up other stats info

      # Files in directory minus 1 = number of images
      @pics = glob(sprintf("Update\\ %02d/*", $upd));

      @pics = grep(!/video\d+$/, @pics);
      $numPics += @pics - 1;

      for (@pics) {
        next if /index.html/;
        $totSize += (-s $_);
      }

      # Needs modifying? Only if either:
      # 1. 'subtract' is set so update number needs moving back
      # 2. this is the last update, and the previous last update has been
      #    removed, so the 'next' link will need removing
      # 3. update(s) were inserted anywhere before this update
      if($subtract || ($upd==$lastUpdate) || ($upd > $inserted)) {
        # Renumber the directory appropriately
        $newUpd = $upd - $subtract;

        rename "Update " . sprintf("%02d", $upd), "Update " . sprintf("%02d", $newUpd);

        # And write/modify it as appropriate
        $checking = 0;
        open(OUT, ">Update " . sprintf("%02d", $newUpd) . "/index.html");
        for (@lines) {
          if($checking) {
            # Fix 'previous chapter' links (remove if this is update 1)
            if(/Previous Chapter/) {
              if($newUpd == 1) {
                $_ = "";
              } else {
                $_ = qq#<A HREF="../Update%20# . (sprintf("%02d", $newUpd-1)) . qq#/index.html"><< Previous Chapter</A><br>\n#;
              }
            # Fix 'next chapter' links (remove if this is the last update)
            } elsif(/Next Chapter/) {
              if($upd == $lastUpdate) {
                $_ = "";
              } else {
                $_ = qq#<A HREF="../Update%20# . (sprintf("%02d", $newUpd+1)) . qq#/index.html">>> Next Chapter</A><br>\n#;
              }
            } 
          }

          # Fix the update number in the page title, change name if applicable
          if(/^<TITLE>/) {
            s#>.+? (- .+<)#>$gameName $1#;

            # Fix chapter title if it wasn't retrieved from the post
            s/ - Chapter \d+</ - Chapter $newUpd</;

            ($chapTitle) = />.+? - (.+)</;
          }

          print OUT ;

          # Start/stop checking for prev/next links
          if(/<!-- begin (header|footer) -->/) {
            $checking = 1;
          } elsif(/<!-- end (header|footer) -->/) {
            $checking = 0;
          }
        }
        close(OUT);
      } else {
        # Just modify the game name
        $newUpd = $upd;

        open(OUT, ">Update " . sprintf("%02d", $newUpd) . "/index.html");
        for (@lines) {
          # Fix the update number in the page title, change name if applicable
          if(/^<TITLE>/) {
            s#>.+? (- .+<)#>$gameName $1#;
            ($chapTitle) = />.+? - (.+)</;
          }
          print OUT ;
        }
        close(OUT);
      }

      $idxTOC .= qq#<li><A HREF="Update%20# . sprintf("%02d", $newUpd) . qq#/index.html">$chapTitle</A><br>\n#;
      if($oldVidStats[$upd]) {
        if($subtract) {
          $oldVidStats[$upd] =~ s/Update $upd:/Update $newUpd:/;
        }
        print V $oldVidStats[$upd];

        # Add to video total
        if($oldVidStats[$upd] =~ /videos/) {
          ($startVid, $endVid) = ($oldVidStats[$upd] =~ /videos (\d+)-(\d+)/);
          for($vidNum=$startVid; $vidNum<=$endVid; $vidNum++) {
            $vidSize += (-s "Videos/video$vidNum"); 
          }
          $numVids += ($endVid - $startVid + 1);
        } else {
          # It said 'video', so there's only 1
          ($vidNum) = ($oldVidStats[$upd] =~ /video (\d+)/);
          $vidSize += (-s "Videos/video$vidNum"); 
          $numVids++;
        }
      }
    } else {
      # Update wasn't there, so add one to the missing count
      print "Removed update $upd\n";
      $subtract++;

      # Remove associated videos
      if($oldVidStats[$upd]) {
        if($oldVidStats[$upd] =~ /videos/) {
          ($startVid, $endVid) = ($oldVidStats[$upd] =~ /videos (\d+)-(\d+)/);
          $rmvVid .= "Removed videos $startVid-$endVid associated with update $upd\n";
        } else {
          ($startVid) = ($oldVidStats[$upd] =~ /video (\d+)/);
          $endVid = $startVid;
          $rmvVid .= "Removed video $startVid associated with update $upd\n";
        }

        for($i=$startVid; $i<=$endVid; $i++) {
          unlink "Videos/video$i";
        }
      }
    }
  }

  # Finish off stats
  print V "- Total videos: $numVids\n";
  printf V "- Total video size: %2.2f MB\n", ($vidSize / 1048576);
  if($rmvVid) { print V "\n$rmvVid"; }

  if($oldErrors) {
     print V "\nErrors (from pre-renum original fetch):\n";
     print V $oldErrors;
  }
  close(V);


  # Read in existing index page (and modify stats)
  $idxHeader = ""; $idxFooter = ""; $doneH1 = 0;
  open(IDX, "<index.html") || die "Couldn't open existing index: $!\n";

  while(<IDX>) {
    if(/<TITLE>/) {
      s#>.+ (- Index<)#>$gameName $1#;
    } elsif(/<h1>/ && ! $doneH1) {
      s#>.+<#>Let's Play $gameName<#;
      $doneH1 = 1;
    }

    if(/First Update/) { $_ = "First Update: $firstDate<br>\n"; }
    elsif(/Last Update/) { $_ = "Last Update: $lastDate<br>\n"; }
    elsif(/Number of Pictures/) { $_ = "Number of Pictures: $numPics<br>\n"; }
    elsif(/Total Size/) { $_ = sprintf("Total Size: %2.2f MB<br>\n", ($totSize / 1048576)); }
    elsif(/Number of Updates/) { $_ = "Number of Updates: $newUpd<br>\n"; }
    elsif(/Pictures per Update/) { $_ = sprintf("Pictures per Update: %2.2f<br>\n", ($numPics / $newUpd)); }
    elsif(/Size per Update/) { $_ = sprintf("Size per Update: %2.2f MB<br>\n", ($totSize / $newUpd / 1048576)); }

    $idxHeader .= $_;
    last if /begin TOC/;
  }

  while(<IDX>) {
    last if /end TOC/;
  }
  $idxFooter .= $_;

  while(<IDX>) { $idxFooter .= $_; }
  close(IDX);

  # Recreate index page with new TOC
  open(IDX, ">index.html") || die "Couldn't recreate index: $!\n";
  print IDX $idxHeader;
  print IDX $idxTOC;
  print IDX $idxFooter;
  close(IDX);
}

__END__

Revision History

2009/06/02 - Fixed the de-mirror-servering, updates are now named
             Update 01, Update 02, etc

2008/12/31 - De-mirror-server waffleimages links

2008/12/01 - Removed fromearth.net reference from $cssURL

2008/09/23 - Pass forums referer to paintedover to get full-size image
             forumimages.somethingawful.com is now fi.somethingawful.com

2008/04/07 - Always accept the OP as a valid chapter

2008/03/28 - Removed all code relating to archives.somethingawful.com
             Added blip.tv as an 'other' video site, removed stage6

2008/03/12 - Smileys are now stored along with the LP

2008/02/20 - Changed 'Date Collected' to 'Date Added'

2008/02/04 - Added code to make wget work more automatically on Mac OS X

2008/01/31 - Trap div-by-zero error caused by empty/failed thread downloads

2008/01/21 - Always apply $newGameName in renum by reusing $gameName

2008/01/08 - Merged fetch-thread and renum-thread

2007/12/31 - Strip trailing #..... stuff from images (eg #via=salr)

2007/12/23 - Line endings in output files should be now be fixed correctly
             $downloadVideos option to prevent download of videos
             $cssURL for changing the location of the css file

2007/12/18 - Smileys in live threads are checked for existence on the
             $smileURL server

2007/12/09 - Failed image downloads will be retried once more at the
             end of the fetch. Any images that needed to be retried
             will be logged, even if they succeeded the second time.

2007/12/06 - Don't download smiley list from server any more, assume all
             smileys :abc: are at $smileURL/emot-abc.gif
             Check to see if they actually exist on the server, generate
             error if not

2007/12/05 - Automatically replace spaces and %xx characters in filenames
             with _s
             Decide whether to automatically name chapters based on the
             percentage of valid automatically-nameable chapters against
             the total number of valid chapters

2007/12/04 - Use otherVidSites to accept posts even if they don't
             contain minImages or any downloadable video contents

2007/11/21 - Renamed vidstats.txt to stats.txt

2007/11/18 - Add total video size to vidstats.txt

2007/11/17 - In the case of multiple links on a line, skip over non-video
             ones until a video one is found (if at all)
             Match chapter titles against word list
             Selected smilies are replaced last

2007/11/12 - Added variable for extra parameters to wget, starting with
             setting the max download retries to 3

2007/11/11 - Fixed $videoPosts to work the way it's described

2007/11/08 - Option (enabled by default) to only use thread author's posts
             Report elapsed time at the end of the script

2007/11/07 - Comments and settings at the top of the script edited for clarity

2007/11/06 - Supports Firefox and Safari cookies on Mac OS X

2007/11/05 - Save videos to a single videos directory, change
             vidstats output to list the video numbers used by
             each update
             Date Collected is auto-filled with today's date

2007/11/03 - Change text smilies to images in archive threads using
             downloaded list

2007/10/31 - Images now retain their original filenames where possible
             Made automatic chapter naming optional

2007/10/29 - Moved fetching images to after the post had been fetched
             (previously this was altering stats if a post had downloaded
             some images but was subsequently rejected)
             Skip fetching existing images (as videos below (2007/10/21))

2007/10/27 - Handle <img width=X src="http://.... for image URLs (used
             in thumbnails)

2007/10/26 - Handle image-only links to videos

2007/10/25 - Video files are now called videoX, not X.flv

2007/10/23 - Chapter titles also used as the <TITLE> for the chapter page now
             Windows: display progress in the title of the console window
             Optional variable to skip wgetting

2007/10/21 - Skip fetching existing videos, except re-fetch the last
             existing video before fetching the next new one

2007/10/20 - Assume the first bold-tagged line in a post is the chapter
             title, and store that for use in the TOC.

2007/10/19 - Added error log to vidstats.txt
             Added 'Collected By' field

2007/10/18 - More recent versions of wget support 303 redirects. Changed to
             expect that.

2007/10/16 - Added automatic cookie detection for Windows Firefox and IE

2007/10/13 - Merged get-source in, using a URL as a parameter to the
             script will fetch that as a forums thread

2007/10/12 - Only take notice of hrefs that are videos. Avoid duplicate hrefs
             Download FLV files for video links

2007/10/09 - Add dummy Backup links after hrefs that point to videos

             A minimum number of images must be present in a post for
             it to be accepted as a chapter (default 2)

             Count posts before starting the fetch, and display progress
             while wgetting images

2007/10/08 - Posts are now not accepted as chapters if the only content
             (images and/or hrefs) in them is inside a [quote] (<blockquote>)

             wget errors now list the image number as well as the chapter
             number

2007/10/07 - Added 'hrefPosts' code to accept posts as chapters if they have
             '<a href=' in them, even if they have no images - useful for
             hybrid LPs where posts may only contain links to videos

2007/10/06 - Quote (\Q...\E) the image URLs used in the search/replace
             operation to avoid regular expression problems with URLs
             containing '?' (or anything else that may come up)


### Revision history for old renum-thread

2007/11/27 - Updates can be inserted by naming them 'Update N.4' (which
             will get renumbered to Update N, move Update N to Update N+1,
             and so on)

2007/11/21 - Renamed vidstats.txt to stats.txt

2007/11/19 - Deleted videos associated with deleted updates

2007/11/18 - Handle total video size in vidstats.txt

2007/11/05 - Update vidstats file correctly in line with the videos
             now being contained in a single subdirectory

2007/10/25 - Video files are now called videoX, not X.flv

2007/10/24 - Preserve chapter titles if they were retrieved from
             the post content (not auto-generated by fetch-thread)
             Update vidstats file

2007/10/09 - Modify game name during renumber if required
