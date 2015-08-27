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
