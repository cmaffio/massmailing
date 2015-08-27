#!/usr/bin/perl
$|=1;
use Net::SMTP_auth;
use FindBin qw($Bin);
use DBI;
use String::Random;

require "$Bin/mass_mailing.conf";
$file_log = "$Bin/mass_mailing.log";
$file_dump = "$Bin/mass_mailing.dump";

my $mittente;
my $destinatario;
my $oggetto;
my $body;
my $cte;
my $ct;

open DUMP, "> $file_dump" or die "cannot open < input.txt: $!" if ($conf{'debug_mailing'});

$dimensione = 0;
while (<>) {
	$dimensione += length;
	print DUMP if ($conf{'debug_mailing'});
	if (/^From: (\".+\" )?<?([\w_\.-]+@[\w\.-]+)>?/) {
		$mittente = $2;
	}

	if (/^To: (\".+\" )?<?([\w_\.-]+@[\w\.-]+)>?/) {
		$destinatario = $2;
	}

	if (/^Subject: (.*)$/) {
		$oggetto = unpack ("H*", $1);
	}

	if (/^Content-Transfer-Encoding: (.*)$/) {
		$cte = unpack ("H*", $1);
	}

	if (/^Content-Type: (.*)$/) {
		$ct = unpack ("H*", $1);
	}

	if (/^$/) {
		$body = "";
		while (<>) {
			$dimensione += length;
			print DUMP if ($conf{'debug_mailing'});
			$body .= $_;
		}
		$body = unpack ("H*", $body);
	}
}

close DUMP if ($conf{'debug_mailing'});
notifica ("$mittente");


my $sql = "SELECT id FROM utenze WHERE mail = '$mittente'";
my $sth = $db->prepare($sql);
my $numrows = $sth->execute();
$numrows = $sth->rows;
if ($numrows == 1) {
	my ($id) = $sth->fetchrow_array;
	$sql = "INSERT INTO ricezioni (id_utenze, arrivata, oggetto, corpo, cte, ct, dimensione) VALUES ($id, NOW(), '$oggetto', '$body', '$cte', '$ct', $dimensione)";
	$sth = $db->prepare($sql);
	$sth->execute();
	my $id_ricezioni = $db->last_insert_id( undef, undef, undef, undef );

	my $random = new String::Random;
	my $messageid = $random->randregex('\d\d\d\d\d\d\d\d\d\d\d\d\d\d\d\d\d\d\d\d\d\d\d\d\d\d\d\d\d\d\d\d'); # 32 numeri

	$sql = "INSERT INTO scheduler (id_utenze, id_ricezioni, stato, inviate, numero, messageid) VALUES ($id, $id_ricezioni, 0, 0, $conf{'blocco'}, $messageid)";
	$sth = $db->prepare($sql);
	$sth->execute();

}

sub notifica {
	my $indirizzo = shift;

	my $oggetto = "Ogetto di test";
	my $corpo = "Questa e' una mail di prova\nvediamo cosa ne esce\n\nCiao";

	my $smtp = new Net::SMTP_auth($conf{'smtp_server'});
	#$smtp->auth ('PLAIN', $sender, $pwd);
	$smtp->mail('no-reply@'.$conf{'server_id'});
	$smtp->recipient($indirizzo, { Notify => ['SUCCESS','FAILURE','DELAY'], SkipBad => 1 });

	$smtp->data();

	$smtp->datasend("To: $indirizzo \n");
	$smtp->datasend("From: <no-reply@".$conf{'server_id'}."> \n");
	$smtp->datasend("Subject: $oggetto\n");
	#$smtp->datasend("Message-Id: <$messageid\@".$conf{'server_id'}.">\n");
	#$smtp->datasend("Content-Transfer-Encoding: $cte\n") if ($cte ne "");
	#$smtp->datasend("Content-Type: $ct\n") if ($ct ne "");

	$smtp->datasend("\n");

	$smtp->datasend($corpo);

	$smtp->datasend("\n");
	$smtp->dataend();
	$smtp->quit;

}
