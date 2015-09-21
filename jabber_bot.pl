#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use Net::Jabber qw(Client);
use File::Slurp;
use Storable;
use WWW::Mechanize;
use MIME::Base64;
use POSIX qw(mkfifo);
use threads;
use threads::shared;
use HTTP::Daemon;
use File::Basename;
use Encode qw(encode);
use HTTP::Status;
use HTTP::Date qw(time2str);
use Config::Tiny;
use Date::Parse;

binmode(STDOUT, ":utf8");

# Dependancies :
# libnet-jabber-perl (Debian) / perl-net-jabber (archlinux)
# libfile-slurp-perl (Debian) / perl-file-slurp (archlinux)
# libcrypt-ssleay-perl(Debian) / perl-crypt-ssleay (archlinux) (for https links)
# libconfig-tiny-perl (Debian) / perl-config-tiny (archlinux)
# perl-timedate (archlinux)

##################### Configuration variables ################################

my $config_file = 'jabber_bot.conf';

my $C = Config::Tiny->new;
$C = Config::Tiny->read( $config_file );

if (! defined $C) {
        print "Could not find config file $config_file.\n";
	print "Please copy it from $config_file.example and fill it appropiately.\n.";
	exit 1;
}

# Connection options configuration (server, login) :
my $server = $C->{Connexion}->{server};
my $room = $C->{Connexion}->{room};
my $con_server = $C->{Connexion}->{con_server};
my $login = $C->{Connexion}->{login};
my $pass = $C->{Connexion}->{pass};

# Dir and file names
my $joke_points_file = $C->{Paths}->{joke_points_file};
my $dir_defs = $C->{Paths}->{dir_defs};
my $dir_quotes = $C->{Paths}->{dir_quotes};
my $file_philosophy = $C->{Paths}->{file_philosophy};
my $FIFOPATH = $C->{Paths}->{fifopath};
my $SHORTENER_URL = $C->{Paths}->{shortener_url};
my $SHORTENER_EXTERNAL_URL = $C->{Paths}->{shortener_external_url};
my $QUOTES_SERVER_PORT = $C->{Paths}->{quotes_server_port};
my $QUOTES_EXTERNAL_URL = $C->{Paths}->{quotes_external_url} . ":$QUOTES_SERVER_PORT/";
my $file_features = $C->{Paths}->{file_features};

# Other
my $own_nick = $C->{Other}->{bot_nick};
my $admin = $C->{Other}->{admin};
my $last_author = $C->{Other}->{sentence_no_author};
my $min_number_for_talking = $C->{Other}->{min_number_for_talking};
my $MIN_LINK_SIZE = $C->{Other}->{min_link_size};
my $MAX_TITLE_SIZE = $C->{Other}->{max_title_size};
my $MECHANIZE_TIMEOUT = $C->{Other}->{mechanize_timeout};
my $MECHANIZE_MAX_SIZE = $C->{Other}->{mechanize_max_size};
my $MIN_WORD_LENGTH = $C->{Other}->{min_word_length};

##################### Other variables ########################################

my %quotes;
my @quotes_all;
my @authors;
my @philo;
my $joke_points;
my $joker = $own_nick;
my $prev_joker = $joker;
my $quiet = 0;
my $cyber_proba = 0;
my $prev_link = "";

############################# Main ###########################################

if (-f $joke_points_file) {
	$joke_points = retrieve($joke_points_file);
}

if (! -d "$dir_defs") {
	mkdir "$dir_defs";
}

opendir(my $DIR, $dir_quotes) or die "cannot open directory $dir_quotes";
my @docs = readdir($DIR);
my $j = 0;
foreach my $d (@docs) {
    my $full_path = "$dir_quotes/$d";
    open (my $res, $full_path) or die "could not open $full_path";
    my $i = 0;
    while(<$res>){
	    utf8::decode($_);
	    $quotes{$d}[$i] = $_;
	    $quotes_all[$j] = $_;
	    $authors[$j] = "$d";
	    $i++;
	    $j++;
    }
    close($res);
}

open (my $res, $file_philosophy) or die "could not open $file_philosophy";
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

# Probability of talking.
# Defaults to 0, gains 0.1 every message. Can be decreased when the bot is told
# to shut up.
my $p = 0;

my $Con = new Net::Jabber::Client();
my $prev_msg = "";
my $prev_nick = "";
my $join_time;

$SIG{HUP} = \&Stop;
$SIG{KILL} = \&Stop;
$SIG{TERM} = \&Stop;
$SIG{INT} = \&Stop;

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

print "Sending presence\n";
$Con->PresenceSend();

join_muc($room, $server, $own_nick);

# Install hook functions:
$Con->SetCallBacks("presence" => \&on_other_join);
$Con->SetMessageCallBacks("groupchat"=>\&on_public, "chat"=>\&on_private);

my $thr = threads->create('monitor_fifo', '');
my $thr2 = threads->create('http_server', '');

while(defined($Con->Process())) {}

Stop();

############################ Submodules #######################################

sub join_muc {
	my ($room, $server, $own_nick) = @_;
	print "Trying to join $room\@$server...\n";
	$Con->MUCJoin(
		room=> $room,
		server=> $server,
		nick=> $own_nick,
	);

	$join_time = time();
}

sub on_public
{
    shift;
    my $message = shift;
    my $text = $message->GetBody();
    my $mess = "";
    my $nick = $message->GetFrom();
    my $resource;
    ($resource, $nick) = split('/', $nick);

    # Do not reply to backlog messages
    my $timestamp = str2time($message->GetTimeStamp());
    if ($timestamp < $join_time) {
	    print "$timestamp : Backlog message : $text\n";
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

    if (($joker ne "") && ($joker ne $nick) && ($text =~ /^[:xX]([Dd]+)/)) {
	    my $nb_d = length $1;
	    $joke_points->{$joker} += $nb_d;
	    print "+$nb_d points blague pour $joker (" . $joke_points->{$joker} . ")\n";
	    # $joker stays the same
	    return;
    } else {
	    $joker = $nick;
    }

    if ($prev_msg eq $text && $prev_nick ne $nick) {
	    $mess = $text;
    } elsif ($text eq "!help") {
	    $mess = "Commandes disponibles :\n";
	    $mess .= "- !ins <Pseudo> <insulte> (en message privé) : envoie anonymement une insulte à la personne ciblée.\n";
	    $mess .= "- !help : affiche cette aide.\n";
	    $mess .= "- !pb : affiche les points-blague\n";
	    $mess .= "- !alias <nick1> <nick2> : donne les points blague de nick2 à nick1\n";
	    $mess .= "- !battle : sélectionne un choix au hasard.\n";
	    $mess .= "- !calc : Calcule une expression mathématique simple.\n";
	    $mess .= "- !cyber [<proba>]: Active le cyber-mode cyber.\n";
	    $mess .= "- !philo : Dicte une phrase philosophique profonde.\n";
	    $mess .= "- !quote [add] [<nick>] [recherche]: Citation aléatoire.\n";
	    $mess .= "- !quote list : Liste tous les auteurs\n";
	    $mess .= "- !quotes <nick> : Donne toutes les citations d'un auteur\n";
	    $mess .= "- !quote search <recherche> : recherche parmi toutes les citations\n";
	    $mess .= "- !related : Citation en rapport\n";
	    $mess .= "- !who : Indique de qui est la citation précédente.\n";
	    $mess .= "- !isit <nick> : Deviner de qui est la citation précédente.\n";
	    $mess .= "- !speak less|more|<number> : diminue/augmente la fréquence des citations aléatoires\n";
	    $mess .= "- !link [lien] : raccourcit le lien passé en paramètre, ou le lien précédent sinon\n";
	    $mess .= "- !! <nom> = <def> : ajouter une définition\n";
	    $mess .= "- !feature add|list : ajouter une demande de feature ou lister toutes les demandes\n";
	    $mess .= "- ?? <nom> : lire une définition";
    } elsif ($text eq "!who") {
	    $mess = "$last_author";
    } elsif ($text =~ /!who\s+(\w+)/ || $text =~ /!isit\s+(\w+)/) {
	    if ($last_author eq "random" or $last_author eq "answer") {
		    $mess = "Ne cherche pas, je n'en sais rien !";
	    }
	    elsif (lc $1 eq lc $last_author) {
		    $mess = "Oui !";
	    } else {
		    $mess = "Non !";
	    }
    } elsif ($text eq "!related") {
	    my $quote_nb = find_related_quote($prev_msg);
	    if ($quote_nb == -1) {
		    $mess .= "Aucune citation trouvée";
	    } else {
		    $mess .= $quotes_all[$quote_nb];
		    chomp($mess);
	    }
    } elsif ($text eq "!quote list") {
	    opendir(my $DIR, $dir_quotes) or die "cannot open directory $dir_quotes";
	    my @docs = grep{ !/^\..*/ } readdir($DIR);
	    foreach my $d (@docs) {
		    my $nb_lines = 0;
		    open(my $f, '<', "$dir_quotes/$d");
		    while (<$f>) {
			    $nb_lines++;
		    }
		    close($f);
		    # Add underscore in the middle of the nick
		    $d =~ s/(.)(.*)/$1_$2/;
		    $mess .= "$d ($nb_lines) ";
	    }
    } elsif ($text eq "!link" && $prev_link ne "") {
	    $mess = shortener($prev_link);
    } elsif ($text =~ /^!link (http(s)?:\/\/[^ ]+)/) {
	    $prev_link = $1;
	    $mess = shortener($1);
    } elsif ($text eq "!speak less") {
	    $min_number_for_talking = int($min_number_for_talking * 1.2);
	    $mess = "Cap fixé à $min_number_for_talking";
    } elsif ($text eq "!speak more") {
	    $min_number_for_talking = int($min_number_for_talking * 0.8);
	    $mess = "Cap fixé à $min_number_for_talking";
    } elsif ($text =~ /^!speak (\d+)$/) {
	    $min_number_for_talking = $1;
	    $mess = "Cap fixé à $min_number_for_talking";
    } elsif ($text =~ /^!battle (.*)/) {
	    my @choices = split(' ', $1);
	    my $rand = rand(scalar @choices);
	    $mess = "$nick : " . $choices[$rand];
	    # Sometimes change answer
	    $rand = int(rand(20));
	    print $rand . "\n";
	    if ($rand == 0) {
		    $mess = "$nick : demain";
	    } elsif ($rand == 1 && scalar @choices == 2) {
		    $mess = "$nick : les deux";
	    }
    } elsif ($text eq "!pb") {
	    return if (!defined $joke_points);
	    foreach my $k (sort { $joke_points->{$b} <=> $joke_points->{$a} } keys $joke_points) {
		    my $tmp = $k;
		    # Add underscore in the middle of nicks when listing joke points
		    $tmp =~ s/(.)(.*)/$1_$2/;
		    $mess .= "$tmp: $joke_points->{$k} points\n";
	    }
	    chomp($mess);
    } elsif ($nick eq $admin && $text =~ /^!pb (.*) ([+-]\d+)/) {
	    $joke_points->{$1} += $2;
	    if ($joke_points->{$1} == 0) {
		    delete $joke_points->{$1};
		    $mess = "$1 retiré de la liste des points blague.";
	    } else {
		    $mess = "$2 points blague pour $1 (" . $joke_points->{$1} . ")";
	    }
    } elsif ($nick eq $admin && $text =~ /!alias (.*) (.*)/) {
	    $joke_points->{$1} += $joke_points->{$2};
	    delete $joke_points->{$2};
	    $mess = "$1 hérite des points blague de $2.";
    } elsif ($text eq "!philo") {
	    # One random phrase from @philo
	    $mess = $philo[rand(scalar @philo)];
    } elsif ($text eq "!quote") {
	    # One random phrase from $quotes{$quote_file}
	    my $quote_nb = rand(scalar @quotes_all);
	    $last_author = $authors[$quote_nb];
	    $mess = convert_quote($quotes_all[$quote_nb], $nick);
    } elsif ($text =~ /^!quote add ([-_\w]+) (.*)$/) {
	    my $theme = $1;
	    my $quote = $2;
	    chomp($quote);
	    my $quote_utf8 = $quote;
	    utf8::encode($quote_utf8);
	    $quotes{$theme}[scalar @{ $quotes{$theme} }] = $quote;
	    my $quote_nb = scalar @quotes_all;
	    $quotes_all[$quote_nb] = $quote; # Also add quote to the array containing all quotes
	    $authors[$quote_nb] = "$1";
	    open (my $quotes_files_fh, '>>', "$dir_quotes/$theme") or die "could not open $dir_quotes/$theme";
	    print $quotes_files_fh $quote_utf8 . "\n";
	    close($quotes_files_fh);
	    $mess = "Citation ajoutée pour $theme : $quote";
    } elsif ($text =~ /^!quote search ([-_\w'’\s]+)\s*$/) {
	    my $search = $1;
	    my $nb_results = 0;
	    # Search for the keyword in all the quotes
	    foreach my $q (@quotes_all) {
		    if ($q =~ /$search/i) {
			    $mess .= $q;
			    $nb_results++;
		    }
	    }
	    chomp($mess);
	    if ($nb_results == 0) {
		    $mess = "Aucune citation trouvée.";
	    } elsif ($nb_results > 5) {
		    # If there are more than 5 results, send a link to
		    # a file containing the results instead
		    if (! -d "quotes/search") {
			    mkdir "quotes/search";
		    }
		    my $filename = $1;
		    # Strip non-ascii character from filename
		    # (HTTP::Daemon does not handle them)
		    $filename =~ s/[^[:ascii:]]//g;
		    if ($filename eq "") {
			    $filename = random_string();
		    }
		    open(my $fh, ">", "quotes/search/" . $filename);
		    print $fh $mess;
		    close($fh);
		    $mess = $QUOTES_EXTERNAL_URL . "search/" . $filename;
	    }
    } elsif ($text =~ /^!quote ([-_\w]+)\s*(.*)$/) {
	    if (defined $quotes{$1}) {
		    if ($2 eq '') {
			    # Give one random quote
			    my $nb_quotes_for_author = scalar @{ $quotes{$1} };
			    my $quote_nb = int(rand($nb_quotes_for_author));
			    $last_author = $1;
			    $mess = convert_quote($quotes{$1}[$quote_nb], $nick);
			    $quote_nb++; # We want actual quote number, not index
			    $mess .= " ($quote_nb/$nb_quotes_for_author)";
		    } else {
			    my $search = $2;
			    # Search for the keyword in all the quotes
			    foreach my $q (@{ $quotes{$1} }) {
				    if ($q =~ /$search/) {
					    $mess .= $q;
				    }
			    }
			    chomp($mess);
			    if ($mess eq "") {
				    $mess = "Aucune citation trouvée.";
			    }
		    }
	    } else {
		    $mess = "Aucune citation trouvée pour $1";
	    }
    } elsif ($text =~ /^!quotes ([-_\w]+)\s*$/) {
	    if (defined $quotes{$1}) {
		    $mess .= $QUOTES_EXTERNAL_URL . $1;
	    } else {
		    $mess = "Aucune citation trouvée pour $1";
	    }
    } elsif ($text =~ /^!calc ([-]?[A-F\d]+\s*([^]\s*[+-]?[A-F\d]+\s*)+)$/) {
	    $mess = "VTFF";
    } elsif ($text =~ /!calc ([-]?[A-F\d]+\s*([+\-*\/]\s*[+-]?[A-F\d]+\s*)+)/) {
	my $res = $1;
	my $scale = ($res =~ /\//)? "scale=3; " : "";
	$mess = "$res = " . `echo "$scale$res" | bc`;
	chomp($mess);
    } elsif ($text =~ /^!cyber\s*0\s*$/) {
	    $cyber_proba = 0;
	    $mess = "Mode cyber désactivé.";
    } elsif ($text =~ /^!cyber (0[.,]\d+)$/) {
	    $cyber_proba = $1;
	    $mess = "Mode cyber: probabilité définie à $1";
    } elsif ($text =~ /^!feature add\s+(.*)/) {
	    my $empty = 0;
	    if (! -f $file_features) {
		    $empty = 1;
	    }
	    open(my $fh, '>>', $file_features);
	    my $feature = $1;
	    # Don't display new line on first line.
	    if ($empty) {
		    print $fh $feature;
	    } else {
		    print $fh "\n" . $feature;
	    }
	    close($fh);
	    $mess .= "Feature request ajoutée : " . $feature;
    } elsif ($text eq '!feature list') {
	    my $empty = 0;
	    open(my $fh, '<', $file_features) or $empty = 1;
	    if ($empty) {
		    $mess = "Aucune feature request. $own_nick est parfait !";
	    } else {
		    while (<$fh>) {
			    if ($_ ne '') {
				    $mess .= $_;
			    }
		    }
		    close($fh);
	    }
    } elsif ($text =~ /(http(s)?:\/\/[^ ]+)/) {
	    $prev_link = $1;
	    $mess = shortener($1);
    } elsif ($text =~ /^(.*?)[,:]? [:xX]([Dd]+)$/) {
	    my $nb_d = length $2;
	    # Only add joke points if the joker already has quote points...
	    # It's easier than tracking who's in the room to know if we laughing
	    # about someone's joke.
	    my $tmp = $joke_points->{$1};
	    if ($1 ne $nick && defined $tmp) {
		    $joker = $1;
		    $joke_points->{$joker} += $nb_d;
		    print "+$nb_d points blague pour $joker (" . $joke_points->{$joker} . ")\n";
	    }
    } elsif ($text =~ /!!\s*([-_\w'’ ]+?)\s*=\s*(.*)\s*$/s) {
	    my $name = $1;
	    my $def = $2;
	    if (-f "$dir_defs/$name") {
		    local $/=undef;
		    open (my $def_file_fh, '<:encoding(UTF-8)', "$dir_defs/$name") or die "could not open $dir_defs/$name";
		    my $prev_def = <$def_file_fh>;
		    close ($def_file_fh);
		    $mess = "Définition modifiée pour $name : $def\nDéfinition précédente : $prev_def";
	    } else {
		    $mess = "Définition ajoutée pour $name : $def";
	    }
	    open (my $def_file_fh, '>:encoding(UTF-8)', "$dir_defs/$name") or die "could not open $dir_defs/$name";
	    print $def_file_fh $def;
	    close($def_file_fh);
    } elsif ($text =~ /\?\?\s*([-_\w'’ ]+?)\s*$/) {
	    my $name = $1;
	    if (! -f "$dir_defs/$name") {
		    $mess = "$name : Non défini";
	    } else {
		    local $/=undef;
		    open (my $def_file_fh, '<:encoding(UTF-8)', "$dir_defs/$name") or die "could not open $dir_defs/$name";
		    $mess = <$def_file_fh>;
		    close ($def_file_fh);
	    }
    }
    else {
	    $p += 1;
	    my $rand = int(rand($min_number_for_talking));
	    #print "$rand, $p\n";
	    if ($rand < $p) {
		    my $quote_nb = find_related_quote($text);
		    if ($quote_nb != -1) {
			    $mess = $quotes_all[$quote_nb];
			    chomp($mess);
			    # To do: find last author here
		    } else {
			    # No related quote found, give a random quote.
			    # scalar @{ $quotes[$index_random] } == size($quotes[$index_random))
			    # in other words, number of quotes in quotes.txt
			    $quote_nb = rand(scalar @quotes_all);
			    $mess = convert_quote($quotes_all[$quote_nb], $nick);
		    }
		    $last_author = $authors[$quote_nb];
	    }
    }
    if ($mess ne "") {
	    if ($cyber_proba > 0) {
		    $mess = cyberize($mess, $cyber_proba);
	    }
	    message($mess);
	    $joker = $own_nick;
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

    my $resource;
    ($resource, $from) = split('/',$from);
    print "===\n";
    print "Presence\n";
    print "  From $from\n";
    print "  Type: $type\n";
    print "  Status: $status ($show)\n";
    print "===\n";

    if ($from eq $own_nick and $type eq "unavailable") {
	    print "Left room (probably got kicked), trying to reconnect.";
	    join_muc($room, $server, $own_nick);
    }
}

sub on_private
{
    shift;
    my $message = shift;
    my $text = $message->GetBody();
    my $nick = $message->GetFrom();
    my $mess = "";

    print "Private message from $nick: $text\n";
    if ($text =~ /^!ins (\w+) (.*)/) {
	priv_message($1, "Quelqu'un vous fait savoir qu'il pense que vous êtes un(e) vrai(e) $2.");
    }
    if ($nick eq "$room\@$server/$admin") {
	    if ($text eq "!save") {
		    store($joke_points, $joke_points_file);
		    $mess = "Points blague sauvegardés.";
	    } elsif ($text =~ /^!pb (.*) ([+-]\d+)/) {
		    $joke_points->{$1} += $2;
		    if ($joke_points->{$1} == 0) {
			    delete $joke_points->{$1};
			    $mess = "$1 retiré de la liste des points blague.";
		    } else {
			    $mess = "$2 points blague pour $1 (" . $joke_points->{$1} . ")";
		    }
	    } elsif ($text =~ /!alias (.*) (.*)/) {
		    $joke_points->{$1} += $joke_points->{$2};
		    delete $joke_points->{$2};
		    $mess = "$1 hérite des points blague de $2.";
	    }
	    if ($mess ne "") {
		    priv_message($admin, $mess);
	    }
    }
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
    unlink($FIFOPATH);
    exit(0);
}

sub shortener {
	my $url = shift;
	my $full_url = $SHORTENER_URL . "?url=" . encode_base64(encode("UTF-8", $url));
	my $mech = WWW::Mechanize->new(autocheck => 0, max_size => $MECHANIZE_MAX_SIZE, timeout=> $MECHANIZE_TIMEOUT);
	my $res = "";
	my $ans = "";
	if (length($url) >= $MIN_LINK_SIZE) {
		$ans = $mech->get($full_url);
		if (!$ans->is_success || $mech->content() eq "hi") {
			print "Failed fetching url $full_url\n";
			return "";
		}
		$res = $SHORTENER_EXTERNAL_URL . $mech->content();
	}

	# Also fetch title
	$ans = $mech->get($url);
	if (!$ans->is_success) {
                print "Failed fetching url $url : " . $mech->status . "\n";
		if ($mech->status eq "404") {
			if ($res ne "") {
				$res .= " ";
			}
			$res .= "404";
		}
	} else {
		my $title = $mech->title();
		if (defined $title) {
			if (length $title gt $MAX_TITLE_SIZE) {
				$title = substr($title, 0, $MAX_TITLE_SIZE);
				chomp($title);
			}
			if ($res ne "") {
				$res .= " ";
			}
			$res .= $title;
		}
	}
	return $res;
}

sub convert_quote {
	my $quote = shift;
	my $nick = shift;
	$quote =~ s/%%/$nick/g;
	utf8::decode($quote);
	chomp($quote);
	return $quote;
}

sub monitor_fifo {
	if (! -p $FIFOPATH) {
		mkfifo($FIFOPATH, 0700) || die "mkfifo failed: $!";
	}

	# if we don't open the fifo in read-write mode, we can't read it with an
	# infinite loop.
	open(my $fifo, "+<", $FIFOPATH) or die "Could not open fifo";

	while(<$fifo>) {
		my $mess = $_;
		chomp($mess);
		utf8::decode($mess);
		print "Received from fifo: $mess\n";
		if ($mess eq "reco") {
			join_muc($room, $server, $own_nick);
		} else {
			message($mess);
		}
	}
}

sub http_server {
	my $d = HTTP::Daemon->new(LocalPort => $QUOTES_SERVER_PORT) || print "Warning: could not start webserver.\n";
	while (my $c = $d->accept) {
		my $r = $c->get_request;
		if ($r) {
			if ($r->method eq "GET") {
				my $path = $r->url->path();
				my $file = fileparse($path); # basename
				if ($path eq "/search/$file") {
					send_file_response($c, "quotes/search/" . $file);
				} else {
					send_file_response($c, "quotes/" . $file);
				}
			}
		}
		$c->close;
		undef($c);
	}
}

# rewrite HTTP::daemon's module because it wouldn't allow one to change headers
sub send_file_response {
	my($self, $file) = @_;
	my $CRLF = "\015\012";   # "\r\n" is not portable
	if (-d $file) {
		$self->send_dir($file);
	}
	elsif (-f _) {
		# plain file
		local(*F);
		sysopen(F, $file, 0) or
		    return $self->send_error(RC_FORBIDDEN);
		binmode(F);
#		my($ct,$ce) = guess_media_type($file);
		# We're working with utf8-encoded files only, and
		# guess_media_type() fails to recognize that.
		my $ct = "text/plain; charset=utf8";
		my($size,$mtime) = (stat _)[7,9];
		unless ($self->antique_client) {
			$self->send_basic_header;
			print $self "Content-Type: $ct$CRLF";
#			print $self "Content-Encoding: $ce$CRLF" if $ce;
			print $self "Content-Length: $size$CRLF" if $size;
			print $self "Last-Modified: ", time2str($mtime), "$CRLF" if $mtime;
			print $self $CRLF;
		}
		$self->send_file(\*F) unless $self->head_request;
		return RC_OK;
	}
	else {
		$self->send_error(RC_NOT_FOUND);
	}
}

sub random_string {
	my @chars = ("a".."z");
	my $string = "";
	$string .= $chars[rand @chars] for 1..8;
	return $string;
}

sub cyberize {
	my($mess, $proba) = @_;
	my $new_mess = $mess;
	my $first = 1;
	while ($mess =~ /(\w{$MIN_WORD_LENGTH,})([ ,\.]|$)/g) {
		if ($first == 1) {
			$first = 0;
		} else {
			my $r = rand;
			print $r;
			if ($r < $proba) {
				# matches the word NOT preceded by "cyber"
				# (so that "foo foo" gets tranformed into
				# "cyberfoo cyberfoo" and not "cybercyberfoo
				# foo")
				$new_mess =~ s/(?<!cyber)($1)/cyber$1/;
			}
		}
	}
	return $new_mess;
}

sub find_related_quote {
	# returns the index of a related quote in @quotes_all
	my $msg = shift;
	my @words;
	# keep words longer than $MIN_WORD_LENGTH
	while ($msg =~ /(\w{$MIN_WORD_LENGTH,})([ ,\.]|$)/g) {
		push @words, $1;
	}
	while (scalar @words != 0) {
		my $r = rand(scalar @words);
		my $word = $words[$r];
		my @related_quotes;
		for $i (0 .. $#quotes_all) {
			if ($quotes_all[$i] =~ /$word/i) {
				push @related_quotes, $i;
			}
		}
		if (scalar @related_quotes > 0) {
			return $related_quotes[rand(scalar @related_quotes)];
		} else {
			delete $words[$r];
		}
	}
	return -1;
}
