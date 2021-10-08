# -----------------------------------------------------------------------------
# PlasticSCM.pm
# 
# Contributed by Patrice Beauvais
# Monster Closet Games
#
# Source Server indexing module for PlasticSCM
# -----------------------------------------------------------------------------

package PLASTICSCM;

require Exporter;
use strict;

our %EXPORT_TAGS = ( 'all' => [ qw() ] );
our @EXPORT_OK   = ( @{ $EXPORT_TAGS{'all'} } );
our @EXPORT      = qw();
our $VERSION     = '0.1';

use Data::Dumper;

# -----------------------------------------------------------------------------
# Simple subs to make it clear when we're testing for BOOL values
# -----------------------------------------------------------------------------
sub TRUE   {return(1);} # BOOLEAN TRUE
sub FALSE  {return(0);} # BOOLEAN FALSE

# -----------------------------------------------------------------------------
# Create a new blessed reference that will maintain state for this instance of
# indexing
# -----------------------------------------------------------------------------
sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = {};
    bless($self, $class);

    #
    # The command to use for talking to the server.  We don't allow this
    # to be overridden at the command line.
    #
    $$self{'PLASTICSCM_CMD'} = "CM.exe";
	
	# Allow environment overrides for these settings.
	$$self{'PLASTICSCMCHANGESET'}  	= $ENV{'PLASTICSCMCHANGESET'}   if (defined $ENV{'PLASTICSCMCHANGESET'});
	$$self{'PLASTICREPOSITORY'}  	= $ENV{'PLASTICREPOSITORY'}   	if (defined $ENV{'PLASTICREPOSITORY'});
	$$self{'PLASTICSERVER'}  		= $ENV{'PLASTICSERVER'}   		if (defined $ENV{'PLASTICSERVER'});

    # Block for option parsing.
    PARSEOPTIONS: {
        my @unused_opts;
        my @opt;

        foreach (@ARGV) {
            # handle command options
            if (substr($_, 0, 1) =~ /^[\/-]$/) {
                # options that set values
                if ( (@opt = split(/=/, $_))==2 ) {
                    block: {
                        $$self{'PLASTICSCMCHANGESET'}   = $opt[1], last if ( uc substr($opt[0], 1) eq "CHANGESET"   );
						$$self{'PLASTICREPOSITORY'}   = $opt[1], last if ( uc substr($opt[0], 1) eq "REPOSITORY"   );
						$$self{'PLASTICSERVER'}   = $opt[1], last if ( uc substr($opt[0], 1) eq "SERVER"   );
                        # Remember this was unused
                        push(@unused_opts, $_);
                        1;
                    }
                # options that are just flags
                }
            } else {
                # Remember this was unused
                push(@unused_opts, $_);
            }
        }

        # Fixup @ARGV to only contained unused options so SSIndex.cmd
        # can warn the user about them if necessary.
        @ARGV = @unused_opts;
    }

    return($self);
}

# -----------------------------------------------------------------------------
# Display module internal option state
# -----------------------------------------------------------------------------
sub DisplayVariableInfo {
    my $self = shift;

    ::status_message("%-15s: %s\n",
                     "PlasticSCM Executable",
                     $$self{'PLASTICSCM_CMD'});
					 
	::status_message("%-15s: %s\n",
                     "PlasticSCM Changeset",
					 $$self{'PLASTICSCMCHANGESET'} ? $$self{'PLASTICSCMCHANGESET'} : "<N/A>");
					 
	::status_message("%-15s: %s\n",
                     "PlasticSCM Repository",
					 $$self{'PLASTICREPOSITORY'} ? $$self{'PLASTICREPOSITORY'} : "<N/A>");
	
	::status_message("%-15s: %s\n",
                     "PlasticSCM Server",
					 $$self{'PLASTICSERVER'} ? $$self{'PLASTICSERVER'} : "<N/A>");
}

# -----------------------------------------------------------------------------
# Given our init data and a local source path, create a lookup table that can
# return individual stream data for each source file.
# -----------------------------------------------------------------------------
sub GatherFileInformation {
    my $self       = shift;
    my $SourceRoot = shift;
    my $ServerRefs = shift;
	my ($Server, $Root, $PreferredAlias, $PreferredServer);	
	
	# This will return a line with the server path and the latest changeset
	my @Files = `$$self{'PLASTICSCM_CMD'} ls -R --format="{path}|{changeset}" --tree=$$self{'PLASTICSCMCHANGESET'}\@$$self{'PLASTICREPOSITORY'}\@$$self{'PLASTICSERVER'} 2>NUL`;

    # For each file, calculate a local file path for the lookup table.
    foreach (@Files) {
		chomp $_;
		
		my $LocalFile = (split /\|/,  $_)[0];
		my $LocalFileWithPath = ($SourceRoot . $LocalFile);
		$LocalFileWithPath=~ s/\//\\/g;
		
		my $FileRevision = (split /\|/,  $_)[1];
		
		@{$$self{'FILE_LOOKUP_TABLE'}{lc $LocalFileWithPath}} = ( { }, "$LocalFileWithPath*$$self{'PLASTICREPOSITORY'}*$LocalFile*$FileRevision*$$self{'PLASTICSERVER'}");
    }
}

# -----------------------------------------------------------------------------
# Return ths SRCSRV stream data for a single file.
# -----------------------------------------------------------------------------
sub GetFileInfo {
    my $self = shift;
    my $file = shift;
			
	# We stored the necessary information when GatherFileInformation() was
    # called so we just need to return that information.
    if ( defined $$self{'FILE_LOOKUP_TABLE'}{lc $file} ) {
		return( @{$$self{'FILE_LOOKUP_TABLE'}{lc $file}} );
    } else {
        return(undef);
    }
}

# -----------------------------------------------------------------------------
# The long name that should be written the SRCSRV stream to describe
# the source control system being indexed.
# -----------------------------------------------------------------------------
sub LongName {
    return("PlasticSCM");
}

# -----------------------------------------------------------------------------
# Set the debug level for output.
# -----------------------------------------------------------------------------
sub SetDebugMode {
	my $self = shift;
}

# -----------------------------------------------------------------------------
# Return the SCS specific stream variables.
# -----------------------------------------------------------------------------
sub SourceStreamVariables {
    my $self = shift;
    my @stream;

    push(@stream, "PLASTICSCM_EXTRACT_CMD=cm.exe cat ".
		 "serverpath:%var3%#cs:%var4%\@rep:%var2%\@repserver:%var5%".
		 "> \"%PLASTICSCM_EXTRACT_TARGET%\"");
    
    push(@stream, "PLASTICSCM_EXTRACT_TARGET=".
                  "%targ%\\%var2%\\%fnbksl%(%var3%)\\%var4%\\%fnfile%(%var1%)");

    return(@stream);
}

# -----------------------------------------------------------------------------
# Loads previously saved file information.
# -----------------------------------------------------------------------------
sub LoadFileInfo {
    my $self = shift;
    my $dir  = shift;
	
    if ( -e "$dir\\plasticscm_files.dat" ) {
        our $FileData1;
        require "$dir\\plasticscm_files.dat";
        $$self{'FILE_LOOKUP_TABLE'} = $FileData1;
    } else {
        ::status_message("No PlasticSCM information saved in $dir.\n");
    }

    return();
}

# -----------------------------------------------------------------------------
# Saves current file information.
# -----------------------------------------------------------------------------
sub SaveFileInfo {
    my $self = shift;
    my $dir  = shift;

    my $fh;
    if ( open($fh, ">$dir\\plasticscm_files.dat") ) {
        $Data::Dumper::Varname = "FileData";
        $Data::Dumper::Indent  = 0;
        print $fh Dumper($$self{'FILE_LOOKUP_TABLE'});
        close($fh);
    } else {
        ::status_message("Failed to save data to $dir.\n");
    }

    return();
}



# -----------------------------------------------------------------------------
# Simple usage ('-?')
# -----------------------------------------------------------------------------
sub SimpleUsage {
print<<PLASTICSCM_SIMPLE_USAGE;
PlasticSCM specific settings:

     NAME            SWITCH      ENV. VAR        	Default
  -----------------------------------------------------------------------------
  A) Changeset      CHANGESET   PLASTICSCMCHANGESET	<n/a>
  B) Repository     REPOSITORY  PLASTICREPOSITORY	<n/a>
  C) Server       	SERVER		PLASTICSERVER 		<n/a>
PLASTICSCM_SIMPLE_USAGE
}

# -----------------------------------------------------------------------------
# Verbose usage ('-??')
# -----------------------------------------------------------------------------
sub VerboseUsage {
print<<PLASTICSCM_VERBOSE_USAGE;
(A)  Changeset - The changeset to sync to

(B)  Repository - The name of the repository in PlasticSCM

(C)  Server - The server address:port

PLASTICSCM_VERBOSE_USAGE
}

1;
__END__
