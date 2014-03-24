#!/usr/bin/perl

use strict;
use warnings;
use utf8;
#use feature 'unicode_strings';

use Net::Jabber qw(Client);
use File::Slurp;

# Configuration des options de connexion (serveur, login) :
my $server = 'chat.jabberfr.org';
my $con_server = 'im.apinc.org';
my $own_nick = 'discussiondiscussion';
my $nb = 0; # bot number
my $admin = 'Perdu';
my $pass = "skldv,slklmLKJsdkf9078";
my $quiet = 0;
my $ignore_msg = 0;

my $dir_quotes = "quotes";
my @quotes;

opendir(DIR, $dir_quotes) or die "cannot open directory $indirname";
my @docs = grep(/\.txt$/,readdir(Dir));
foreach $d (@docs) {
    $full_dir = "$dir_quotes/$d";
    open (my res, $full_dir) or die "could not open $full_dir";
    while(<res>){
	    @quotes = read_file($file_quotes);
	    # todo: array of arrays

    }
}

my $room = "test";
if (@ARGV > 0) {
	$room = shift;
}

# Informations concernant le Bot :
# my $version = '1.0';

# Probability of talking.
# Defaults to 0, gains 0.1 every message. Can be decreased when the bot is told
# to shut up.
my $p = 0;

my $Con = new Net::Jabber::Client();
my $prev_msg = "";
my $prev_nick = "";

$SIG{HUP} = \&Stop;$SIG{KILL} = \&Stop;$SIG{TERM} = \&Stop;$SIG{INT} = \&Stop;

# Connect and auth
$Con->Connect(hostname => $con_server);
if($Con->Connected()) {
	print "We are connected to the server...\n";
} else {
        print "Couldn't connect to the server... Please check your server configuration\n";
	exit 1;
}

my @result = $Con->AuthSend(username => $own_nick,
			    password => $pass,
			    resource => "Bot"
		    );

if ($result[0] ne "ok") {
  die "Ident/Auth with server failed: $result[0] - $result[1]\n";
}
#if($result[0] eq "401") { tryregister(); }

print "Sending presence\n";
$Con->PresenceSend();

print "Trying to join $room$server...\n";
$Con->MUCJoin(
	room=> $room,
	server=> $server,
	nick=> $own_nick,
);

my $join_time = time();

# "message" => \&on_public,
# Install hook functions:
$Con->SetCallBacks("presence" => \&on_other_join);
$Con->SetMessageCallBacks("groupchat"=>\&on_public);

while(defined($Con->Process())) {}



#sub tryregister {
#	print "Failed to authenticate, trying to register...\n";
#	my @result = $Con->RegisterSend(username => $username,
#					resource => "Bot",
#					password => $pass,
#					email    => "tohwiq\@gmail.com",
#					key      => "wat"
#				 );
#	print "RegisterSend", \@result;
#}


#sub on_connect() {
#    my ($conn, $event) = @_;
#    print "Joining $channel...";
#    $conn->join($channel);
#
#    use Data::Dumper;
#    print Data::Dumper->Dump([\$conn, \$event], [qw(conn event)]);
#
#    $conn->{'connected'} = 1;
#}

sub on_public
{
    shift;
    my $message = shift;
    my $text = $message->GetBody();
    my $mess = "";
    my $nick = $message->GetFrom();
    my $resource;
    ($resource, $nick) = split('/', $nick);

    # Ugly workaround to the fact that backlog messages are considered as
    # normal messages: ignores messages during the first 5 seconds (a raspberry
    # pi is slow)
    if (time() < $join_time + 5) {
	    return;
    }

    if (!defined $nick || $nick eq "" || $nick eq $own_nick || $text eq "") {
	    return;
    }

    print "<" . $nick . ">\t| $text\n";

    if ($nick eq $admin && $text eq '!q') {
	$quiet = 1;
	print "Becoming quiet.\n";
    } elsif ($nick eq $admin && $text eq '!nq') {
	$quiet = 0;
	print "Stop being quiet.\n";
    }
    if ($quiet == 1) {
	return;
    }

    if ($prev_msg eq $text && $prev_nick ne $nick) {
	    message($text);
	    $prev_nick = $nick;
	    return;
    } else {
	    $prev_msg = $text;
	    $prev_nick = $nick;
    }

    $p += 1;

    if ($text =~ /!help/) {
	my $mess2 = "Commandes disponibles :";
	message($mess2);
	$mess2 = "- !ins <Pseudo> <insulte> (en message privé) : envoie anonymement une insulte à la personne ciblée.";
	message($mess2);
	$mess2 = "- !help : affiche cette aide.";
	message($mess2);
	return;
    }

#    if (int(rand(10)) < 8) {
#	    return;
#    }

    if ($text =~ /([-]?[A-F\d]+\s*([+\-*\/^]\s*[+-]?[A-F\d]+\s*)+)/) {
	my $res = $1; 
	my $scale = ($res =~ /\//)? "scale=3; " : ""; 
	$mess = "$res = " . `echo "$scale$res" | bc`;
    } elsif ($text =~ /(?:^|\W)(connard|pd|pédé|fdp|gay|retardé|mac-user|con|
                        débile|polard|noob)(?:\W|$)/ix) {
	$mess = "C'est toi le $1 $nick.";
    } elsif ($text =~ /(?:^|\W)(enculé|enculay|enculasse|enfoiré|enflure|
                                homosexuel|attardé|autiste|trisomique|abruti
                        )(?:\W|$)/ix) {
	$mess = "C'est toi l'$1 $nick.";
    } elsif ($text =~ /(?:^|\W)(tafiole|tapette|tata|conne|pute|salope|merde|
                        putain|crevure|enflure|pétasse|tepu|teupu)(?:\W|$)/ix) {
	$mess = "C'est toi la $1 $nick.";
    } elsif ($text =~ /(?:^|\W)$own_nick(?:\W|$)/i) {
	$mess = "N'ose même pas m'adresser la parole, sale sous-merde de $nick.";
    } elsif ($text =~ /(?:^|\W)(windows|mac)(?:\W|$)/i) {
	$mess = "Aaah $1 c'est caca.";
    } elsif ($text =~ /(?:juif|nazi|hitler|nsdap|sieg|heil)/i) {
	$mess = "ARBEIT MACHT FREI !";
    } elsif ($text =~ /(?:^|\W)(bite|teub)(?:\W|$)/i) {
	$mess = "A propos de $1... $nick, tu veux pas sucer la mienne ?";
    } elsif ($text =~ /(?:^|\W)je suis (.*)\./i) {
	$mess = "Les $1 sont vraiment des connards.";
    } elsif (int(rand(10)) < $p) {
	$mess = $quotes[rand(scalar(@quotes))];
	utf8::decode($mess);
#	$mess = "tg fdp de $nick.";
    }
    if ($mess ne "") {
	message($mess);
    }
}

sub on_other_join
{
    shift;
    my $presence = shift;
    return unless $presence->GetFrom("jid");
    my $from = $presence->GetFrom() || "";
    my $type = $presence->GetType() || "";
    my $status = $presence->GetStatus() || "";
    my $show = $presence->GetShow() || "";

    # Ugly workaround, see in sub on_public
    if (time() < $join_time + 2) {
	    return;
    }

    my $resource;
    ($resource, $from) = split('/',$from);
    print "===\n";
    print "Presence\n";
    print "  From $from\n";
    print "  Type: $type\n";
    print "  Status: $status ($show)\n";
    print "===\n";

   if ($from ne $own_nick) {
       message("Vas-y casse-toi enculaÿ de $from.");
   }
}

sub on_private
{
    my ($conn, $event) = @_;
    my $text = $event->{'args'}[0];
    if ($text =~ /^!ins (\w+) (.*)/) {
	message($1, "Quelqu'un vous fait savoir qu'il pense que vous êtes un(e) vrai(e) $2."); 
    } #else {
#	message($event->{'nick'}, "vtff $event->{'nick'}");
#    }
}

sub on_other_part
{
   my ($conn, $event) = @_;
   message("Enfin débarrassé de ce sale enfoiré $event->{'nick'} !");
   print "<" . $event->{'nick'} . ">Déconnexion.\n";
}

# Reconnect to the server when we die.
sub on_disconnect {
    my ($self, $event) = @_;

    print "Disconnected from ", $event->from(), " (",
    ($event->args())[0], "). Attempting to reconnect...\n";
    $self->connect();
}

sub message {
	my $body = shift;
	my $msg = Net::Jabber::Message->new();
	$p = 0;
	$msg->SetMessage(
		"type" => "groupchat",
		"to" => "$room\@$server",
		"body" => $body,

);
	$Con->Send($msg);
#	$Con->MessageSend(to => $room . $server,
#			  body => $msg);
}

sub Stop {
    print "Exiting...\n";
    $Con->Disconnect();
    exit(0);
}
