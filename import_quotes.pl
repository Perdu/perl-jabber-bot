#!/usr/bin/perl

use strict;
use warnings;
use utf8;
use DBI;
use Config::Tiny;
use Unicode::Collate;

my $config_file = 'jabber_bot.conf';

my $C = Config::Tiny->new;
$C = Config::Tiny->read( $config_file );

my $dir_quotes = $C->{Paths}->{dir_quotes};
my $MIN_WORD_LENGTH = $C->{Other}->{min_word_length};

# Database
my $db_name = $C->{Database}->{db_name};
my $db_server = $C->{Database}->{db_server};
my $db_user = $C->{Database}->{db_user};
my $db_pass = $C->{Database}->{db_pass};
my $db_port = $C->{Database}->{db_port};

my $dbh = open_db($db_name, $db_server, $db_port, $db_user, $db_pass);

# We need an accent-insensitive case-insensitive compare for mysql
my $insensitive_cmp = Unicode::Collate->new(
	level         => 1,
	normalization => undef
);

opendir(my $DIR, $dir_quotes) or die "cannot open directory $dir_quotes";
my @docs = readdir($DIR);
my $j = 0;
foreach my $d (@docs) {
    my $full_path = "$dir_quotes/$d";
    open (my $res, $full_path) or die "could not open $full_path";
    my $i = 0;
    while(<$res>){
	    my $quote = $_;
	    chomp($quote);
	    my $query = $dbh->prepare("
		INSERT INTO quotes (author, quote)
		VALUES (?, ?)");
	    $query->execute($d, $quote);
	    my $q_quote_add_words = $dbh->prepare("
		INSERT INTO words_in_quote (quote_id, word)
		VALUES (?,?)");
	    my @words = get_words($quote);
	    my $prev_id = $dbh->{mysql_insertid};
	    foreach (@words) {
		    $q_quote_add_words->execute($prev_id, $_);
	    }
	    add_words_links($quote);

    }
    close($res);
}

## Copy-paste from jabber_bot.pl
# Yes, it's ugly, but perl is not python

sub open_db {
	my($db_name, $db_server, $db_port, $db_user, $db_pass) = @_;
	my $dbh = DBI->connect( "DBI:mysql:database=$db_name;host=$db_server;port=$db_port",
				$db_user, $db_pass, {
					RaiseError => 1,
				}
			) or die "Could not connect to database $db_name\n $! \n $@\n$DBI::errstr";
	return $dbh;
}

sub known_word {
	my @words = @{$_[0]};
	my $word = $_[1];
	foreach (@words) {
		if ($insensitive_cmp->eq($word, $_)) {
			return 1;
		}
	}
	return 0;
}

sub get_words {
	my $msg = shift;
	utf8::decode($msg);
	my @words;
	# keep words longer than $MIN_WORD_LENGTH
	while ($msg =~ /(\w{$MIN_WORD_LENGTH,})([ ,\.\-']|$)/g) {
		my $word = $1;
		if (! known_word(\@words, $word)) {
			push @words, $word;
		}
	}
	return @words;
}

sub add_words_links {
	my $text = shift;
	my @words = get_words($text);
	my $q_add_words_links = $dbh->prepare("
		INSERT INTO words_links (word1, word2, occurences)
		VALUES(?, ?, 1)
		ON DUPLICATE KEY UPDATE occurences = occurences + 1;
	");
	foreach (@words) {
		my $word1 = $_;
		foreach (@words) {
			if ($word1 ne $_) {
				$q_add_words_links->execute($word1, $_);
			}
		}
	}
}
