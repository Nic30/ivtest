#!/usr/bin/perl -s
##!/utilities/perl/bin/perl -s
#
# Script sregress.pl modified to handle vvp for Steve Williams
#
# Copyright (c) 1999 Guy Hutchison (ghutchis@pacbell.net)
#
#    This source code is free software; you can redistribute it
#    and/or modify it in source code form under the terms of the GNU
#    General Public License as published by the Free Software
#    Foundation; either version 2 of the License, or (at your option)
#    any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program; if not, write to the Free Software
#    Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA
#
# 3/25/2001  SDW   Modified sregress.pl script to run vvp.
# 4/13/2001  SDW   Added CORE DUMP detection
# $Log: vvp_reg.pl,v $
# Revision 1.16  2002/08/18 17:00:33  ka6s
# Changed arguments to cmp to "cmp -i $ignorebytes f1 f2" from "cmp f1 f2 $ignorebytes $ignorebytes"
#
# Revision 1.15  2002/08/10 14:58:17  ka6s
# Added -S option detection. So normal,-S will cause a -S flag.
#
# Revision 1.14  2002/07/03 23:57:35  stevewilliams
#  Clean up test temporary files.
#
# Revision 1.13  2002/01/06 17:01:10  ka6s
# Added CE support.
#
# Revision 1.12  2001/10/08 22:14:42  sib4
# Remove absolute path names for IVL executable
#
# Revision 1.11  2001/10/08 22:13:30  sib4
# assert portability
#
# Revision 1.10  2001/10/08 22:11:50  sib4
# diff=file:file:ignore
#
# Revision 1.9  2001/08/06 02:59:27  ka6s
# Added test for PR126 - constant assign to bus part from memory
#
# Revision 1.8  2001/07/08 03:19:16  sib4
# Add COMPERR check
#
# Revision 1.7  2001/06/26 00:41:41  sib4
# Will we finally have that LF at the end
#
# Revision 1.6  2001/05/18 13:24:10  ka6s
# Detect sorry as well as the others..
#
# Revision 1.5  2001/04/14 03:44:03  ka6s
# Added what I THINK is working redirection. The Parse Err is showing up now!
#
# Revision 1.4  2001/04/14 03:33:02  ka6s
# Fixed detection of Core dumps. Made sure I remove core before we run vvp.
#

#  Global setup and paths
$| = 1;             # This turns off buffered I/O 
$total_count = 0;
$debug = 1;

$num_opts = $#ARGV ;

if($num_opts ne -1) {
   # Got here cuz there is a command line option
   $regress_fn = $ARGV[0];
   if(!( -e "$regress_fn")) {
       print("Error - Command line option file $num_opts doesn't exist.\n");   
       exit(1);
   }
} else {
   $regress_fn = "./regress.list";
}


$logdir = "log";
$bindir = "bin";  # not currently used
$report_fn = "./regression_report.txt";

$comp_name = "IVL" ;	# Change the name of the compiler in use here.
                        # this may change to a command line option after
		        		# I get things debugged!

   $vername = "iverilog";	    # IVL's shell 
   $versw   = "";			    # switches
   $verout  = "-o simv -tvvp";	# vvp source output (for IVL ) 
   #$redir = "&>";
   $redir = "> ";

#  Main script

print ("Reading/parsing test list\n");
&read_regression_list;
&rmv_logs ;
&execute_regression;
print ("Checking logfiles\n");
&check_results;

#
# Remove log files
#

sub rmv_logs {
 foreach (@testlist) {
   $cmd = "rm -rf log/$_.log";
   system("$cmd");
 }
}

#
#  parses the regression list file
#
#  splits the data into a list of names (@testlist), and a
#  number of hashes, indexed by name of test.  Hashes are
#  (from left-to-right in regression file):
#
#    %testtype     type of test.  compile = compile only
#                                 normal = compile & run, expect standard
#                                     PASSED/FAILED message at EOT.
#    %testpath     path to test, from root of test directory.  No
#                  trailing slash on test path.
#
#    %testmod = main module declaration (optional)

sub read_regression_list {    
    open (REGRESS_LIST, "<$regress_fn");
    local ($found, $testname);

    while (<REGRESS_LIST>) {
	chop;
	if (!/^#/) {
	    # strip out any comments later in the file
	    s/#.*//g;
	    $found = split;
	    if ($found > 2) {
         $total_count++;
		$testname = $_[0];
		$testtype{$testname} = $_[1];
		$testpath{$testname} = $_[2];

        if($#_ eq 3)  {                    # Check for 4 fields
           if(!($_ =~ /gold=/) && !($_ =~ /diff=/ )) {
             $testmod{$testname} = $_[3];  # Module name, not gold
             $opt{$testname} = "";         # or diff
           } elsif ($_ =~ /gold=/) {
             $testmod{$testname} = "" ;	   # It's a gold file
             $opt{$testname} = $_[3] ; 
           } elsif ($_ =~ /diff=/) {	   # It's a diff file
             $testmod{$testname} = "";
             $opt{$testname} = $_[3];     
           }
        } elsif ($#_ eq 4) {             # Check for 5 fields
           $testmod{$testname} = $_[3];  # Module name - always in this case
           if ($_ =~ /gold=/) {
             $opt{$testname} = $_[4];                   
           } elsif ($_ =~ /diff=/) {
             $opt{$testname} = $_[4];                   
           }
        }

		push (@testlist, $testname);
	    }
	  }
    }

    close (REGRESS_LIST);
}

#
#  execute_regression sequentially compiles and executes each test in
#  the regression.  Regression is done as a two-pass run (execute, check
#  results) so that at some point the execution part can be parallelized.
#

sub execute_regression {
    local ($testname, $rv);
    local ($bpath, $lpath, $vpath);

    foreach $testname (@testlist) {
   
        #
        # First lets clean up if its' IVL. We need to know if 
        # these are generated on the current pass.
        #

        #
        # This is REALLY only an IVL switch...
        #
        # vermod is used to declare the "main module"
        #
        if( $testmod{$testname} ne "") {
           $vermod = "-s ".$testmod{$testname} ;
        } else {
           $vermod = " ";
        }

	print "Test $testname:";
	if ($testpath{$testname} eq "") {
	  $vpath = "./$testname.v";
	} else {
	  $vpath = "./$testpath{$testname}/$testname.v";
	}

	$lpath = "./$logdir/$testname.log";
        system("rm -rf $lpath");  
        system("rm -rf *.out");  

        # Check here for "compile only" situation and set
        # the switch appropriately.
        #
        # While we're in CO mode - take a snapshot of it. Note
        # this puts a contraint on the order -never can have a CO
        # as the FIRST test in the list for this to work. 
        #

        if($testtype{$testname} ne "CO") {	# Capture ONLY
            $versw = $old_versw ;			# the non-compile only
        }									# command here.
         
        if(($testtype{$testname} eq "CO") ||
           ($testtype{$testname} eq "CN")) {
             if($testtype{$testname} eq "CN") {
                  $versw = "-t null";
             } else {
                  $versw = ""; 	 
             }
        } else { 
          $versw = $old_versw ;	 # Restore non-compile only state
        }

        if($testtype{$testname} =~ /-S/) {
            $versw = $versw." -S";
        }
         
        #
        # if we have a logfile - remove it first
        #
        if(-e "$lpath") {
           system("rm $lpath");
        }
          
        #
        # Now build the command up
        #
	#	$cmd = "$vername $versw $vermod $verout $vpath &> $lpath ";
		$cmd = "$vername $versw $vermod $verout $vpath $redir $lpath 2>&1 ";

	print "$cmd\n";
	$rc = system("$cmd");

        # Note that with IVL we have to execute the code now
        # that it's compiled - there is GOING to be switch in 
        # the verilog switch that will make this unnecessary. 
  
        if(($rc == 0) && ($comp_name eq "IVL")) {
              if( -e "simv") {
                 if(!($testtype{$testname} eq "CO" ) &&
                    !($testtype{$testname} eq "CN" ) && 
                    !($testtype{$testname} eq "CE" )) {
                   system ("rm -rf core");
                   system ("vvp simv >> $lpath 2>&1 ");
                 } else {
                   
                 }
                 if( -e "core") {
                    system ("echo CRASHED >> $lpath" );
                 }
              } elsif ( -e "core") {
                  system ("echo CRASHED >> $lpath" );
               
              } elsif ($testtype{$testname} eq "CN" ) {
                  # system ("echo PASSED >> $lpath" );
              } else {
                  system ("echo COMPERR >> $lpath" );
              }
        } else {
              system ("echo COMPERR $rc >> $lpath" );
        }
 
    }

}

sub check_results {
    local ($testname, $rv);
    local ($bpath, $lpath, $vpath);
    local ($pass_count, $fail_count, $crash_count);
    local ($result);

    $pass_count  = 0;
    $no_sorry  = 0;
    $parse =0;
    $no_run      = 0;
    $crash_count = 0;
    $comperr_cnt = 0;
    $comp_err = 0;
    $unhandled = 0;
    $unable = 0;
    $assertion = 0;
    $passed = 0;
    $failed = 0;

    open (REPORT, ">$report_fn");

    print REPORT "Test Results:\n";

    foreach $testname (@testlist) {
	$lpath = "$logdir/$testname.log";
    
    #
    # This section is used to compare against GOLD FILES
    # We compare the log file against a known GOOD result
    #
    # This section runs if gold=name is the 4th option
    #
     
    $gold_file = "";
    $gold_file = "";
    $diff_file = "";
    $optname = $opt{$testname} ;
    if(($opt{$testname} ne "")  && ($optname  =~ /gold=/)){
      $gold_file = $opt{$testname};
      $gold_file =~ s/gold=//;		# remove gold= operator
      system("rm -rf ./dfile");
      system("diff $lpath ./gold/$gold_file > ./dfile ");
      if( -z "dfile" ) {
        system ("echo PASSED >> $lpath" );
	system ("rm -f $testname.*");
      } else {
        system ("echo FAILED >> $lpath");
      }
    }
    
    $gold_file = "";
    $diff_file = "";
    #
    # Now look for difference file requirements - use this for
    # vcd's initially I guess. 
    #
    if(($opt{$testname} ne "")  && ($optname  =~ /diff=/)){
      $diff_file = $optname ;
      $diff_file =~ s/diff=//;
      system("rm -rf ./dfile");	
      ($out_file,$gold_file,$ignbytes) = split(/:/,$diff_file);
      if( $ignbytes ne "" ) {
        system("cmp -i $ignbytes $out_file $gold_file > ./dfile");
      } else {
        system("diff $out_file $gold_file > ./dfile");
      }
      if( -z "dfile" ) {
        system ("echo PASSED >> $lpath" );
	system ("rm -f $testname.*");
      } else {
        system ("echo FAILED >> $lpath");
      }
    }

	# uncompress the log file, if a compressed log file exists
	if (-f "$lpath.gz") { system "gunzip $lpath.gz"; }

	# check the log file for the test status
	if (-f $lpath) {
		print ("Checking test $lpath\n");
		$result = `tail -150 $lpath`;
   
        $err_flag = 0;

		# First do analysis for all tests that SHOULD run

        printf REPORT "%30s ",$testname;

	if(	($testtype{$testname} ne "CE") &&  
	  ($testtype{$testname} ne "CN")) {
	   # 
	   # This section is true for all tests that execute - 
	   # no matter the compiler.
	   #
            if ($result =~ "Unhandled")  {
               $err_flag = 1;
               printf REPORT "Unhandled-"; 
               $unhandled++;
            }
            if ($result =~ "failing")  {
               $err_flag = 1;
               printf REPORT "synth failed-"; 
            }

            if ($result =~ "sorry")  {
               $err_flag = 1;
               printf REPORT "Sorry-"; 
               $unhandled++;
            }

            if (($result =~ "parse") ||($result =~ "ERROR"))  {
               $err_flag = 1;
               printf REPORT "Parse Err-"; 
               $parse++;
            }

            if ($result =~ "Unable" ) {
               $err_flag = 1;
               printf REPORT "Unable-"; 
               $unable++;
            }
            
            if ($result =~ "[Aa]ssertion" ) {
               $err_flag = 1;
               printf REPORT "Assertion-"; 
               $assertion++;
            }
            if ($result =~ "CRASHED" ) {
               $err_flag = 1;
               printf REPORT "Ran-CORE DUMP-"; 
               $failed++;
            }
            if ($result =~ "COMPERR" ) {
               $err_flag = 1;
               printf REPORT "Compiler Error-"; 
               $comperr_cnt++;
               $failed++;
            }

            if($testtype{$testname} ne "CO") {
              if ($result =~ "PASSED" ) {
                 printf REPORT "Ran-PASSED-"; 
                 $passed++;
		 system ("rm -f $testname.*");
              }

              if ($result =~ "FAILED" ) {
                 printf REPORT "Ran-FAILED-"; 
                 $failed++;
              }

            } else {
              if(-z $lpath) {
                 printf REPORT "CO-PASSED-"; 
                 $passed++;
		 system ("rm -f $testname.*");
                } else {
                 printf REPORT "CO-FAILED-"; 
                 $failed++;
                }              
            }
          
            printf REPORT "\n";
        } elsif($testtype{$testname} eq "CE") {
            if($result =~ "COMPERR") {
               printf REPORT "CE-PASSED-\n";
               $passed++;
	       system ("rm -f $testname.*");
            } else {
               printf REPORT "CE-FAILED-\n";
               $failed++;
            }
	} else {
            printf REPORT "\n";
        }
      }
    }
    $total = $pass_count + $no_compile + $no_run + $crash_count;
    print REPORT "Tests passed: $passed, failed: $failed, Unhandled: $unhandled Unable: $unable, Assert: $assertion, Parse Errs: $parse\n";
    print         "Tests passed: $passed, failed: $failed, Unhandled: $unhandled Unable: $unable, Assert: $assertion  Parse Errs: $parse\n";

    close (REPORT);
}
