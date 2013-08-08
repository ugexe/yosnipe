use v5.10;
use utf8;
use AnyEvent;
use AnyEvent::Strict;
use AnyEvent::IRC::Client;
use AnyEvent::HTTP::LWP::UserAgent;
use Getopt::Long::Descriptive;

our $VERSION = '0.0.3';

my ($opt, $usage) = describe_options(
    "$0 %o <some-arg>",
    [ 'server|s=s',  "the server to connect to",     { default => 'irc.synirc.net'  }],
    [ 'port|p=i',    "the port to connect to",       { default => 6667              }],
    [ 'nick|n=s',    "the nick for sniepbot to use", { default => 'rms_snipa'       }],
    [ 'password:s',  "the password for your nick",                                   ],
    [ 'join|j=s',    "default channel to join",      { default => '#yospos'         }],
    [ 'reply|r',     "use link to post a reply directly [instead of end of thread]", ],
    [ 'f5=i',        "seconds between checks",       { default => 20                }],
    [ 'verbose|v',   "verbose (not really)",                                         ],
    [],
    [ 'help|h',      "print usage message and exit" ],
);
say $usage->text, exit if $opt->help;

my $NICK         = $opt->nick;
my $HOST         = $opt->server;
my $PORT         = $opt->port;
my $PASSWORD     = $opt->password?$opt->password:undef;
my $CHANNEL      = $opt->join;
my $VERBOSE      = $opt->verbose?1:0;
my $URL_REPLY    = $opt->reply?1:0;
my $REFRESH_RATE = $opt->f5;
############################################################


my $C             = AnyEvent->condvar; 
my $AEIRC         = AnyEvent::IRC::Client->new;
my $UA = AnyEvent::HTTP::LWP::UserAgent->new;
my $THREADS       = {}; # prevent repeat snipe alerts. thread_id => post_count

my $timer; 

$AEIRC->reg_cb(
    connect => sub {
        my ($irc, $err) = @_;
        if (defined $err) { warn ("connect error: $err\n") if $VERBOSE; return; }
        warn ("Connected to irc server\n") if $VERBOSE;
        $irc->send_srv(PRIVMSG => 'NickServ', "identify $PASSWORD") if defined $PASSWORD;
    },
    disconnect => sub { # I should re-connect
        warn ("Disconnected, waiting 30 secs to reconnect.\n") if $VERBOSE;
        my $w; $w = AnyEvent->timer( after => 30, cb => sub {
            warn ("Attempting to reconnect on IRC") if $VERBOSE;
            $AEIRC->connect( $HOST, $PORT, { nick => $NICK } );
            $AEIRC->send_srv( "JOIN", $CHANNEL );
            undef $w;
        });
    }, 
    join => sub {
        my ($irc, $nick, $chan, $is_myself) = @_; 
        say "Joined $chan" if $VERBOSE;
        if ($is_myself) {
            $timer = AnyEvent->timer(after => 1, interval => $REFRESH_RATE, cb => sub {
                my $yospos_url = 'http://forums.somethingawful.com/forumdisplay.php?forumid=219';
                warn "Getting $yospos_url\n" if $VERBOSE;
                $UA->get_async($yospos_url)->cb( sub{
                    my $r = shift->recv;
                    my $content = $r->content;

                    while( $content =~ m{<tr class="thread" id="thread(?<thread_id>\d+)">.*?<td class="replies">(?<reply_count>\d+)</td>.*?</tr>}gs ) {
                        my $reply_count = $+{reply_count};
                        my $thread_id   = $+{thread_id};

                        if( ( ($reply_count+1) % 40 ) == 0 && 
                            ( $THREADS->{$thread_id} != $reply_count || 
                              $reply_count > $THREADS->{$thread_id} ) )  {

                            warn ('ThreadID: ' . $thread_id . '@' . $reply_count . "\n") if $VERBOSE;

                            my $irc_url = $URL_REPLY?
                                       "http://forums.somethingawful.com/newreply.php?action=newreply&threadid=$thread_id":
                                       "http://forums.somethingawful.com/showthread.php?threadid=$thread_id&goto=lastpost";

                            my $tinyurl_url = "http://tinyurl.com/api-create.php?url=$irc_url";
                            warn "\tGetting $tinyurl_url\n" if $VERBOSE;
                            $UA->get_async($tinyurl_url)->cb( sub {
                                my $r2 = shift->recv;
                                my $tinyurl = $r2->content;
                                warn ("\tTinyURL: " . $tinyurl) if $VERBOSE;
                                $THREADS->{$thread_id} = $reply_count;
                                $irc->send_chan( $chan, PRIVMSG => ($chan, "snipez: $tinyurl") );
                            });
                        } 
                    }   
                });
            });
        }
    },
);

$AEIRC->connect( $HOST, $PORT, { nick => $NICK } );
$AEIRC->send_srv( "JOIN", $CHANNEL );
$C->recv;


1;


__END__


=encoding utf8

=head1 NAME

yosnipe - yospos sniping made available to IRC

=head1 SYNOPSIS

    < wesley_snipez> snipez: http://tinyurl.com/cyrr9ya
    # a SomethingAwful thread open to snipe

=head1 DESCRIPTION

ban op gas thread

=head1 BUGS

Please report bugs to:

L<http://forums.somethingawful.com/showthread.php?threadid=3502502>

=head1 AUTHOR

uG

=head1 LICENSE AND COPYRIGHT

This library is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

=cut