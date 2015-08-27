#!/usr/bin/perl
$|=1;
use Net::SMTP_auth;
use FindBin qw($Bin);
use DBI;
use String::Random;

require "$Bin/mass_mailing.conf";
$file_log = "$Bin/mass_mailing.log";

# Ricerca delle mail da inviare
my $sql = "SELECT id, id_ricezioni, numero, id_liste, messageid, stato FROM scheduler WHERE data_invio <= NOW() AND stato BETWEEN 1 AND 9";

my $sth = $db->prepare($sql);
my $numrows = $sth->execute();
$numrows = $sth->rows;

while (my ($id_scheduler, $id_ricezione, $numero, $id_liste, $messageid, $stato) = $sth->fetchrow_array) {
	invio ($id_scheduler, $id_ricezione, $id_liste, $numero, $messageid, $stato);
}

sub invio {
	my $id_scheduler = shift;
	my $id_ricezione = shift;
	my $id_liste = shift;
	my $numero = shift;
	my $messageid = shift;
	my $stato_invio = shift;

	# Caricamento dei dati della mail da inviare
	my $sql = "SELECT ricezioni.id_utenze, ricezioni.oggetto, ricezioni.corpo, ricezioni.cte, ricezioni.ct, utenze.mail, utenze.sasl_pwd FROM ricezioni JOIN utenze ON ricezioni.id_utenze = utenze.id WHERE ricezioni.id = $id_ricezione";
	my $sth = $db->prepare($sql);

	my $numrows = $sth->execute();
	$numrows = $sth->rows;
	if ($numrows == 1) {
		my ($id_utenze, $oggetto, $corpo, $cte, $ct, $sender, $pwd) = $sth->fetchrow_array;
		$oggetto = pack ("H*", $oggetto);
		$corpo = pack ("H*", $corpo);
		$cte = pack ("H*", $cte);
		$ct = pack ("H*", $ct);
		
		$pwd = pack ("h*", pack ("H*", $pwd));

		# Ricerca degli indirizzi a cui inviare
		my $sql = "SELECT id, indirizzo, nome FROM destinatari WHERE id_utenze = $id_utenze AND stato = 1 AND id_liste = $id_liste AND id NOT IN (SELECT id_destinatari FROM invii WHERE id_scheduler = $id_scheduler) LIMIT $numero";

		$sth = $db->prepare($sql);
		$sth->execute();
		my $numrows = $sth->rows;

		if ($numrows == 0) {
			my $sql = "UPDATE scheduler SET data_termine = NOW(), stato = 10 WHERE id = $id_scheduler";
			my $sth1 = $db->prepare($sql);
			$sth1->execute();

		} else {
			while (my ($id_destinatari, $indirizzo, $nome) = $sth->fetchrow_array) {

				my $messageid = "$id_destinatari.$messageid";
		
				my $smtp = new Net::SMTP_auth($conf{'smtp_server'});
				$smtp->auth ('PLAIN', $sender, $pwd);
				$smtp->mail('reply@'.$conf{'server_id'});
				$smtp->recipient($indirizzo, { Notify => ['SUCCESS','FAILURE','DELAY'], SkipBad => 1 });
		
				$smtp->data();
	
				$smtp->datasend("To: \"$nome\" <$indirizzo> \n");
				$smtp->datasend("From: <$sender> \n");
				$smtp->datasend("Subject: $oggetto\n");
				$smtp->datasend("Message-Id: <$messageid\@".$conf{'server_id'}.">\n");
				$smtp->datasend("Content-Transfer-Encoding: $cte\n") if ($cte ne "");
				$smtp->datasend("Content-Type: $ct\n") if ($ct ne "");

				$smtp->datasend("\n");

				$smtp->datasend($corpo);

				$smtp->datasend("\n");
				$smtp->dataend();
				$smtp->quit;

				$sql = "INSERT INTO invii (id_utenze, id_ricezione, id_destinatari, data, message_id, stato, id_scheduler) VALUES ($id_utenze, $id_ricezione, $id_destinatari, NOW(), '$messageid', 0, $id_scheduler)";
				my $sth1 = $db->prepare($sql);
				$sth1->execute();

				my $aggiunta = "data_inizio = NOW(), stato = 2, " if ($stato_invio == 1);
				$sql = "UPDATE scheduler SET $aggiunta inviate=inviate+1 WHERE id = $id_scheduler";
				$sth1 = $db->prepare($sql);
				$sth1->execute();
			}
		}
	}
}

