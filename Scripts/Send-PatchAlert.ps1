param(
    [Parameter(Mandatory)][string]$From,
    [string]$To         = "admin@entreprise.local",
    [string]$SmtpServer = "smtp.gmail.com",
    [int]   $Port       = 587,
    [switch]$NoSsl
)

$Dossier    	   = "C:\Users\local-admin\Desktop"
$cheminConformite  = Join-Path $Dossier "ComplianceReport.csv"
$cheminRapportHTML = Join-Path $Dossier "Rapport_Securite.html"
$cheminCred        = Join-Path $Dossier "smtp.cred.xml"
$cheminLog         = Join-Path $Dossier "Patch_Manager.log"

function Write-AuditLog {
    param([string]$Message)
    $ligne = "{0}; {1}" -f (Get-Date).ToString("dd/MM/yyyy HH:mm:ss"), $Message
    Add-Content -Path $cheminLog -Value $ligne -Encoding UTF8
    Write-Host $ligne
}

if (-not (Test-Path $cheminConformite)) {
    Write-AuditLog "ERREUR; ComplianceReport.csv introuvable ; notification non envoyée"
    return
}

$lignes = @(Import-Csv -Path $cheminConformite -Delimiter ";" -Encoding Default)
$nc     = @($lignes | Where-Object { $_.'État'.Trim() -eq "NON CONFORME" })
$inac   = @($lignes | Where-Object { $_.'État'.Trim() -eq "INACCESSIBLE" })

if (($nc.Count + $inac.Count) -eq 0) {
    Write-AuditLog "Aucune anomalie détectée ; notification non nécessaire"
    return
}

$dateControle = ([string]$lignes[0].'Date du contrôle').Split(" ")[0]
$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine("Date du contrôle : $dateControle")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("Postes contrôlés      : $($lignes.Count)")
[void]$sb.AppendLine("Postes non conformes  : $($nc.Count)")
[void]$sb.AppendLine("Postes inaccessibles  : $($inac.Count)")
[void]$sb.AppendLine("")
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
    if (Test-Path $cheminRapportHTML) { $mail.Attachments = $cheminRapportHTML }

    Send-MailMessage @mail
    Write-AuditLog "Notification envoyée à $To"
} catch {
    Write-AuditLog "ERREUR; Notification non envoyée; $($_.Exception.Message)"
}
