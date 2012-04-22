#!/usr/bin/perl
#
# My hideous first perl script!
# Stefanie Edgar
# Feb 2012
#
# netbench.pl
# A script to run network benchmarks on remote hosts and return the results.
# Useful for testing out new network settings across cluster nodes.

use strict;
use warnings;
use IO::Handle;

# remote hosts to run network benchmarks on
my @hosts = qw(192.168.12.1 192.168.12.2 192.168.12.3 192.168.12.4 192.168.12.5 192.168.12.6 192.168.12.7 192.168.12.8 192.168.12.9);

# configuration
# choose between one or more network benchmark tests to run
my $conf={
        debug        =>        0,
        iperf        =>        1,
        netperf      =>        1,
        netpipe      =>        0,
        path         =>        {
                               iperf        =>        "/usr/bin/iperf",
                               netpipe      =>        "/usr/bin/NPtcp",
                               netperf      =>        "/usr/bin/netperf",
                               netserver    =>        "/usr/bin/netserver",
                               iperf        =>        "/usr/bin/iperf",
                               ssh          =>        "/usr/bin/ssh",
                               },
};

# For each host, create a child processes to start the background daemons remotely.
# Then locally run the client benchmark program for that host.
foreach my $host (@hosts)
{
        # Store the PIDs of the child processes in this hash as they're spawned.
        my %pids;

        print "============ Network Benchmarks for $host ============ \n";

        # -- fork for netpipe -- #
        defined(my $pid=fork) or die "Can't fork, error: [$!].\n";
        if ($pid)
        {
                # record child pid in the hash. 
                $pids{$pid}=1;
        }
        else
        {
                # Start up the background daemon on the remote hosts.
                print "netpipe fork: started. \n" if $conf->{debug};
                print "netpipe fork: calling function call_netpipe_on_remote($host) \n" if $conf->{debug};
                call_netpipe_on_remote($host);

                # When the function returns, this child fork exits. 
                # Though, netpipe won't exit without being killed,
                # so I'll have to make sure to kill netpipe after
                # the test has run. Until then, this will stay running.

                print "fork: exiting\n" if $conf->{debug};
                exit;
        }


        # -- fork for netperf -- #
        defined(my $pid=fork) or die "Can't fork, error: [$!].\n";
        if ($pid)
        {
                $pids{$pid}=1;
        } 
        else
        {
               call_netperf_on_remote($host);
                exit;
        }
        
        # -- fork for iperf -- #
        defined(my $pid=fork) or die "Can't fork, error: [$!].\n";
        if ($pid)
        {
               $pids{$pid}=1;
        } 
        else
        {
                print "iperf fork: started. \n" if $conf->{debug};
                print "iperf fork: calling function call_iperf_on_remote($host) \n" if $conf->{debug};
                call_iperf_on_remote($host);
                print "iperf fork: exiting\n" if $conf->{debug};
                exit;
        }

        # wait for daemons to get set up, then run client-side benchmarks on the local machine
        sleep 3;
        run_local_netpipe($host) if $conf->{netpipe};
        run_local_iperf($host) if $conf->{iperf};
        run_local_netperf($host) if $conf->{netperf};
}

#############
# Functions #
#############

sub call_netpipe_on_remote
{
    print "call_netpipe_on_remote: function started. \n" if $conf->{debug};

    # param passed to function, tells where to run NetPIPE
    my $host = shift;

    print "call_netpipe_on_remote: calling kill_remote_process($host, $conf->{path}{netpipe}) \n" if $conf->{debug};
    kill_remote_process($host, $conf->{path}{netpipe});
    sleep 1; # wait for process to die before proceeding

    print "call_netpipe_on_remote: attempting to start NetPIPE on $host\n" if $conf->{debug};

    # create file handle, then specify a shell command to start the load generator
    my $fh=IO::Handle->new();
    my $sc="$conf->{path}{ssh} root\@$host \"$conf->{path}{netpipe} 2>&1\"";

    # open the file handle, using the command and catching the output
    open ($fh, "$sc 2>&1 |") or die "Failed to call: [$sc], error was: $!\n";

    while(<$fh>)
    {
        my $line=$_;
        print "$line\n" if $conf->{debug};
    }
    $fh->close();

    print "call_netpipe_on_remote: exiting. \n" if $conf->{debug};
}

sub call_netperf_on_remote 
{
    print "call_netperf_on_remote: function started. \n" if $conf->{debug};
    my $host = shift;

    print "call_netperf_on_remote: calling kill_remote_process($host, $conf->{path}{netserver}) \n" if $conf->{debug};
    kill_remote_process($host, $conf->{path}{netserver});

    sleep 1; # wait for process to die before proceeding

    print "call_netperf_on_remote: attempting to start NetPerf on $host\n" if $conf->{debug};
    my $fh=IO::Handle->new();
    my $sc="$conf->{path}{ssh} root\@$host \"$conf->{path}{netserver} \"";
    open ($fh, "$sc 2>&1 |") or die "Failed to call: [$sc], error was: $!\n";

    while(<$fh>)
    {
        my $line=$_;
        print "$line\n" if $conf->{debug};
    }
    $fh->close();
    print "call_netperf_on_remote: Netperf\'s netserver runs as a daemon, so this fork doesnt need to stay open. Exiting. \n" if $conf->{debug};
}


sub call_iperf_on_remote
{
    print "call_iperf_on_remote: function started\n" if $conf->{debug};

    my $host = shift;
    print "call_iperf_on_remote: calling kill_remote_process($host, iperf) \n" if $conf->{debug};
    kill_remote_process($host, "iperf");
 
    print "call_iperf_on_remote: attempting to start iperf on $host\n" if $conf->{debug};
    my $fh=IO::Handle->new();
    my $sc="$conf->{path}{ssh} root\@$host \"$conf->{path}{iperf} -s --bind $host\"";
    open ($fh, "$sc 2>&1 |") or die "Failed to call: [$sc], error was: $!\n";
    print "call_iperf_on_remote: iperf daemon started on $host\n" if $conf->{debug};
 
    while(<$fh>)
    {
        chomp;
        my $line=$_;
        print "$line\n" if  $conf->{debug};
    }
    $fh->close();
    print "call_iperf_on_remote: exiting. \n" if $conf->{debug};
}

sub kill_remote_process
{
        print "kill_remote_process: function started.\n" if $conf->{debug};
        # params
        my ($host, $process) = @_;

        print "kill_remote_process: killing all $process on $host\n" if $conf->{debug};
        my $fh=IO::Handle->new();
        my $sc="$conf->{path}{ssh} root\@$host killall $process";
	open ($fh, "$sc 2>&1 |") or die "Failed to call: [$sc], error was: $!\n";

	while(<$fh>)
	{
            my $line=$_;
            print "$line\n" if $conf->{debug};
	}
	$fh->close();
        print "kill_remote_process: exiting.\n" if $conf->{debug};

}

sub run_local_netpipe
{
    print "run_local_netpipe: function started.\n" if $conf->{debug};
    my $host=shift;
    my $fh=IO::Handle->new();
    my $sc="$conf->{path}{netpipe} -h $host 2>&1 | tail -n 10";
    open ($fh, "$sc 2>&1 |") or die "Failed to call: [$sc], error was: $!\n";
	while(<$fh>)
	{
            chomp;
            my $line=$_;
            print "$line\n";
	}
    $fh->close();
    print "run_local_netpipe: post-run. calling kill_remote_process($host, $conf->{path}{netpipe}) \n" if $conf->{debug};
    kill_remote_process($host, $conf->{path}{netpipe});
}

sub run_local_iperf
{
    print "run_local_iperf: function started.\n" if $conf->{debug};
    my $host=shift;
    my $fh=IO::Handle->new();
    my $sc="$conf->{path}{iperf} -c $host |tail -n 1";
    open ($fh, "$sc 2>&1 |") or die "Failed to call: [$sc], error was: $!\n";
	while(<$fh>)
	{
		chomp;
		my $line=$_;
		print "$line\n";
	}
	$fh->close();
        print "run_local_iperf: FH closed. killing off remaining iperf process.\n" if $conf->{debug};
        kill_remote_process($host, "iperf"); 
}

sub run_local_netperf
{
    print "run_local_netperf: function started. \n" if $conf->{debug};
    my $host=shift;
    my $fh=IO::Handle->new();
    my $sc="$conf->{path}{netperf} -l 30 -H $host 2>&1 | tail -n 6";
    open ($fh, "$sc 2>&1 |") or die "Failed to call: [$sc], error was: $!\n";
        while(<$fh>)
        {
            my $line=$_;
            print "$line"; # missing \n here intentially. Netperf has its own newlines.
        }
    $fh->close();
    print "run_local_netperf: post-run cleanup. Calling kill_remote_process($host, $conf->{path}{netserver}) \n" if $conf->{debug};
    kill_remote_process($host, $conf->{path}{netserver}); 
    print "run_local_netperf: Exiting. \n" if $conf->{debug};
}


