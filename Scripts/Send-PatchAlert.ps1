# ==================================================================================================
# Send-PatchAlert.ps1 – Partie 7 : notification par e-mail
# Rôle : lit ComplianceReport.csv et n'envoie un e-mail à l'administrateur QUE s'il y a au moins un poste NON CONFORME ou INACCESSIBLE. Le rapport HTML est joint. Chaque envoi (réussi ou en échec) est tracé dans Patch_Manager.log.
# Usage : .\Send-PatchAlert.ps1 -From "expediteur@exemple.com" -To "admin@exemple.com" -SmtpServer smtp.ethereal.email -Port 587
# Sécurité : aucun mot de passe dans le script. L'identifiant SMTP est lu dans smtp.cred.xml, créé une fois avec : Get-Credential | Export-Clixml smtp.cred.xml (mot de passe chiffré par DPAPI, utilisable seulement par le même compte Windows sur la même machine).
# Test sans authentification : option -NoSsl avec un serveur local.
# ==================================================================================================

param(
    # Paramètres : l'expéditeur est obligatoire ; le destinataire (administrateur), le serveur SMTP et le port ont une valeur par défaut modifiable.
    [Parameter(Mandatory)][string]$From,
    [string]$To         = "admin@entreprise.local",
    # Pour Ethereal Email, utiliser smtp.ethereal.email (port 587).
    [string]$SmtpServer = "smtp.gmail.com",
    [int]   $Port       = 587,
    [switch]$NoSsl
)

# Dossier de travail et chemins des fichiers lus ou écrits (smtp.cred.xml = identifiant SMTP chiffré).
$Dossier    	   = "C:\Users\local-admin\Desktop"
$cheminConformite  = Join-Path $Dossier "ComplianceReport.csv"
$cheminRapportHTML = Join-Path $Dossier "Rapport_Securite.html"
$cheminCred        = Join-Path $Dossier "smtp.cred.xml"
$cheminLog         = Join-Path $Dossier "Patch_Manager.log"

# Écrit une ligne horodatée dans le journal commun (Patch_Manager.log) et l'affiche à l'écran.
function Write-AuditLog {
    param([string]$Message)
    $ligne = "{0}; {1}" -f (Get-Date).ToString("dd/MM/yyyy HH:mm:ss"), $Message
    Add-Content -Path $cheminLog -Value $ligne -Encoding UTF8
    Write-Host $ligne
}

# Sans ComplianceReport.csv, il n'y a rien à analyser : on le journalise et on sort du script (return).
if (-not (Test-Path $cheminConformite)) {
    Write-AuditLog "ERREUR; ComplianceReport.csv introuvable ; notification non envoyée"
    return
}

# Détection des anomalies : relecture du résultat de la conformité et isolement des postes NON CONFORME et INACCESSIBLE.
$lignes = @(Import-Csv -Path $cheminConformite -Delimiter ";" -Encoding Default)
$nc     = @($lignes | Where-Object { $_.'État'.Trim() -eq "NON CONFORME" })
$inac   = @($lignes | Where-Object { $_.'État'.Trim() -eq "INACCESSIBLE" })

# Aucune anomalie : le script se termine SANS envoyer de mail (exigence du sujet), mais laisse une trace
# dans le journal.
if (($nc.Count + $inac.Count) -eq 0) {
    Write-AuditLog "Aucune anomalie détectée ; notification non nécessaire"
    return
}

# Construction du corps du message avec un StringBuilder. [void] évite d'afficher la valeur renvoyée par chaque AppendLine.
$dateControle = ([string]$lignes[0].'Date du contrôle').Split(" ")[0]
$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine("Date du contrôle : $dateControle")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("Postes contrôlés      : $($lignes.Count)")
[void]$sb.AppendLine("Postes non conformes  : $($nc.Count)")
[void]$sb.AppendLine("Postes inaccessibles  : $($inac.Count)")
[void]$sb.AppendLine("")
# Détail des postes en anomalie : l'état, puis un KB manquant par ligne. Les postes conformes ne sont pas listés.
foreach ($l in $lignes) {
    $etat = $l.'État'.Trim()
    if ($etat -eq "NON CONFORME") {
        [void]$sb.AppendLine("$($l.Poste) : NON CONFORME")
        foreach ($kb in ($l.'Liste des KB manquantes' -split ",")) {
            [void]$sb.AppendLine("        $($kb.Trim()) manquante")
        }
        [void]$sb.AppendLine("")
    } elseif ($etat -eq "INACCESSIBLE") {
        [void]$sb.AppendLine("$($l.Poste) : INACCESSIBLE")
        [void]$sb.AppendLine("")
    }
}

# Envoi du mail. Les paramètres sont regroupés dans une table de hachage puis passés avec @mail («splatting»), ce qui permet d'en ajouter selon le cas.
try {
    $mail = @{
        SmtpServer    = $SmtpServer
        Port          = $Port
        From          = $From
        To            = $To
        Subject       = "[PATCH MANAGEMENT] Anomalies détectées"
        Body          = $sb.ToString()
        Encoding      = [System.Text.Encoding]::UTF8
        ErrorAction   = 'Stop'
        WarningAction = 'SilentlyContinue'   # Send-MailMessage est marqué obsolète
    }
    if (-not $NoSsl) {
        $mail.UseSsl     = $true
        $mail.Credential = Import-Clixml -Path $cheminCred
    }
    # Joint le rapport HTML de la partie 6 s'il existe.
    if (Test-Path $cheminRapportHTML) { $mail.Attachments = $cheminRapportHTML }

    Send-MailMessage @mail
    Write-AuditLog "Notification envoyée à $To"
} catch {
    # Échec d'envoi (serveur injoignable, identifiant refusé...) : trace d'erreur dans le journal, le script ne plante pas.
    Write-AuditLog "ERREUR; Notification non envoyée; $($_.Exception.Message)"
}
