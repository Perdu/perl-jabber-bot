#!/usr/bin/perl

use strict;
use warnings;
use utf8;
#use feature 'unicode_strings';

use Net::Jabber qw(Client);
use File::Slurp;
use Storable;

# Dépendances :
# libnet-jabber-perl (Debian) / perl-net-jabber (archlinux)
# libfile-slurp-perl (Debian) / perl-file-slurp (archlinux)

# Configuration des options de connexion (serveur, login) :
my $server = 'chat.jabberfr.org';
my $room = "ensimag"; # also first param
my $con_server = 'im.apinc.org';
my $login = 'discussiondiscussion';
my $own_nick = 'anu';
my $nb = 0; # bot number
my $admin = 'Perdu';
my $pass = "skldv,slklmLKJsdkf9078";
my $quiet = 0;
my $ignore_msg = 0;
my $joke_points_file = "points_blague";

my $dir_quotes = "quotes";
my @quotes;
my $file_philosophie = "zoubida.txt";
my @philo;

my $index_random;
my $joke_points;

if (-f $joke_points_file) {
	$joke_points = retrieve($joke_points_file);
}

opendir(my $DIR, $dir_quotes) or die "cannot open directory $dir_quotes";
my @docs = grep(/\.txt$/,readdir($DIR));
my $file_count = 0;
foreach my $d (@docs) {
	if ($d eq "quotes.txt") {
		$index_random = $file_count;
	}
    my $full_path = "$dir_quotes/$d";
    open (my $res, $full_path) or die "could not open $full_path";
    # First line is special
    $quotes[$file_count][0] = <$res>;
    my $i = 1;
    while(<$res>){
	    $quotes[$file_count][$i] = $_;
	    $i++;
	    # todo: array of arrays

    }
    $file_count++;
}

if (!defined $index_random) {
	print STDERR "quotes.txt not found\n";
	exit 1;
}

open (my $res, $file_philosophie) or die "could not open $file_philosophie";
my $i = 1;
while(<$res>){
	$philo[$i] = $_;
	chomp($philo[$i]);
	utf8::decode($philo[$i]);
	$i++;
}

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

my @result = $Con->AuthSend(username => $login,
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
$Con->SetMessageCallBacks("groupchat"=>\&on_public, "chat"=>\&on_private);

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
    if (time() < $join_time + 10) {
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
	    $mess = $text;
    } elsif ($text eq "!help") {
	    $mess = "Commandes disponibles :\n";
	    $mess .= "- !ins <Pseudo> <insulte> (en message privé) : envoie anonymement une insulte à la personne ciblée.\n";
	    $mess .= "- !help : affiche cette aide.\n";
	    $mess .= "- !pb : affiche les points-blague\n";
	    $mess .= "- !battle : sélectionne un choix au hasard.\n";
	    $mess .= "- !calc : Calcule une expression mathématique simple.\n";
	    $mess .= "- !philo : Dicte une phrase philosophique profonde.";
    } elsif ($text =~ /^!battle (.*)/) {
	    my @choices = split(' ', $1);
	    my $rand = rand(scalar @choices);
	    $mess = "$nick : " . $choices[$rand];
    } elsif (($prev_nick ne "") && ($prev_nick ne $nick) && ($text =~ /^[:xX]([Dd]+)/)) {
	    my $nb_d = length $1;
	    $joke_points->{$prev_nick} += $nb_d;
	    print "+$nb_d points blague pour $prev_nick (" . $joke_points->{$prev_nick} . ")\n";
    } elsif ($text eq "!pb") {
	    return if (!defined $joke_points);
	    foreach my $k (sort { $joke_points->{$b} <=> $joke_points->{$a} } keys $joke_points) {
		    my $tmp = $k;
		    # Add underscore in the middle of nicks when listing joke points
		    $tmp =~ s/(.)(.*)/$1_$2/;
		    $mess .= "$tmp: $joke_points->{$k} points\n";
	    }
	    chomp($mess);
    } elsif ($text eq "!philo") {
	    # One random phrase from @philo
	    $mess = $philo[rand(scalar @philo)];
    } elsif ($text =~ /^!calc ([-]?[A-F\d]+\s*([^]\s*[+-]?[A-F\d]+\s*)+)$/) {
	    $mess = "VTFF";
    } elsif ($text =~ /!calc ([-]?[A-F\d]+\s*([+\-*\/]\s*[+-]?[A-F\d]+\s*)+)/) {
	my $res = $1;
	my $scale = ($res =~ /\//)? "scale=3; " : "";
	$mess = "$res = " . `echo "$scale$res" | bc`;
	chomp($mess);
    } #elsif ($text =~ /(?:^|\W)(connard|pd|pédé|fdp|gay|retardé|mac-user|con|
#                        débile|polard|noob)(?:\W|$)/ix) {
#	$mess = "C'est toi le $1 $nick.";
#    } elsif ($text =~ /(?:^|\W)(enculé|enculay|enculasse|enfoiré|enflure|
#                                homosexuel|attardé|autiste|trisomique|abruti
#                        )(?:\W|$)/ix) {
#	$mess = "C'est toi l'$1 $nick.";
#    } elsif ($text =~ /(?:^|\W)(tafiole|tapette|tata|conne|pute|salope|merde|
#                        putain|crevure|enflure|pétasse|tepu|teupu)(?:\W|$)/ix) {
#	$mess = "C'est toi la $1 $nick.";
#    } elsif ($text =~ /(?:^|\W)$own_nick(?:\W|$)/i) {
#	$mess = "N'ose même pas m'adresser la parole, sale sous-merde de $nick.";
#    } elsif ($text =~ /(?:^|\W)(windows|mac)(?:\W|$)/i) {
#	$mess = "Aaah $1 c'est caca.";
#    } elsif ($text =~ /(?:juif|nazi|hitler|nsdap|sieg|heil)/i) {
#	$mess = "ARBEIT MACHT FREI !";
#    } elsif ($text =~ /(?:^|\W)(bite|teub)(?:\W|$)/i) {
#	$mess = "A propos de $1... $nick, tu veux pas sucer la mienne ?";
#    } elsif ($text =~ /(?:^|\W)je suis (.*)\./i) {
#	$mess = "Les $1 sont vraiment des connards.";
#    } else {
	    $p += 1;
	    my $rand = int(rand(100));
	    #print "$rand, $p\n";
#	    if ($rand < $p) {
		    # scalar @{ $quotes[$index_random] } == size($quotes[$index_random)
		    # in other words, number of quotes in quotes.txt
#		    $mess = $quotes[$index_random][rand(scalar @{ $quotes[$index_random] })];
#		    utf8::decode($mess);
#		    chomp($mess);
#	    }
#    }
    if ($mess ne "") {
	message($mess);
    }

    $prev_msg = $text;
    $prev_nick = $nick;
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

}

sub on_private
{
    shift;
    my $message = shift;
    my $text = $message->GetBody();
    my $nick = $message->GetFrom();

    print "Private message from $nick: $text\n";
    if ($text =~ /^!ins (\w+) (.*)/) {
	priv_message($1, "Quelqu'un vous fait savoir qu'il pense que vous êtes un(e) vrai(e) $2.");
    }
    if ($nick eq "$room\@$server/$admin") {
	    if ($text eq "!save") {
		    store($joke_points, $joke_points_file);
		    priv_message($admin, "Points blague sauvegardés.");
		    print "Points blague sauvegardés.\n";
	    }
    }

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

sub message_send {
	my $dest = shift;
	my $body = shift;
	my $msg = Net::Jabber::Message->new();
	$p = 0;
	$msg->SetMessage(
		"type" => "groupchat",
		"to" => "$dest",
		"body" => $body,

);
	$Con->Send($msg);
	print "<$own_nick> | " . $body . "\n";
}


sub message {
	my $body = shift;
	message_send("$room\@$server", $body);
}

sub priv_message {
	my $dest = shift;
	my $body = shift;
	my $full_dest = "$room\@$server/$dest";
	print "Private message to $dest: $body\n";
	$Con->MessageSend(to=>$full_dest, body=>$body);
}

sub Stop {
    print "Exiting...\n";
    $Con->Disconnect();
    store($joke_points, $joke_points_file);
    exit(0);
}
