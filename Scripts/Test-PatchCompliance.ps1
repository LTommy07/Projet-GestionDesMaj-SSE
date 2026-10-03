$Dossier = "C:\Users\local-admin\Desktop"
$fichierInventaire = Join-Path $Dossier "computers.txt"
$fichierRequis     = Join-Path $Dossier "required-patches.txt"
$cheminCSV         = Join-Path $Dossier "ComplianceReport.csv"
$cheminLog         = Join-Path $Dossier "Patch_Manager.log"

function Write-AuditLog {
    param([string]$Message)
    $ligne = "{0}; {1}" -f (Get-Date).ToString("dd/MM/yyyy HH:mm:ss"), $Message
    Add-Content -Path $cheminLog -Value $ligne -Encoding UTF8
    Write-Host $ligne
}

if (-not (Test-Path $fichierRequis)) { throw "Fichier introuvable : $fichierRequis" }
$requis = @(Get-Content -Path $fichierRequis -Encoding Default |
    ForEach-Object { $_.Trim().ToUpper() } |
    Where-Object { $_ -match '^KB\d+$' } | Sort-Object -Unique)
if ($requis.Count -eq 0) { throw "Aucun KB valide dans $fichierRequis" }

Write-AuditLog "Début du contrôle de conformité ($($requis.Count) KB requis)"

$dateControle = (Get-Date).ToString("dd/MM/yyyy HH:mm:ss")
$ordinateurs  = Get-Content -Path $fichierInventaire -Encoding Default
$resultats    = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($ligne in $ordinateurs) {
    if ([string]::IsNullOrWhiteSpace($ligne)) { continue }
    $nom, $ip = $ligne -split ";"
    $nom = $nom.Trim(); $ip = $ip.Trim()

    $etat = $null; $installes = @(); $manquants = @()

    if (-not (Test-Connection -ComputerName $ip -Count 1 -Quiet)) {
        $etat = "INACCESSIBLE"
    } else {
        try {
            $installes = @(Invoke-Command -ComputerName $ip -ErrorAction Stop -ScriptBlock {
                (Get-HotFix).HotFixID
            } | ForEach-Object { "$_".ToUpper() })
        } catch {
            $etat = "INACCESSIBLE"
            Write-AuditLog "$nom; ERREUR WinRM; $($_.Exception.Message)"
        }
    }

    if (-not $etat) {
        $manquants = @($requis | Where-Object { $installes -notcontains $_ })
        $etat = if ($manquants.Count -eq 0) { "CONFORME" } else { "NON CONFORME" }
    }

    $resultats.Add([PSCustomObject]@{
        'Poste'                    = $nom
        'Adresse IP'               = $ip
        'KB requises'              = $requis.Count
        'KB manquantes'            = if ($etat -eq "INACCESSIBLE") { "-" } else { $manquants.Count }
        'Liste des KB manquantes'  = if ($etat -eq "INACCESSIBLE") { "-" } else { $manquants -join "," }
        'État'                     = $etat
        'Date du contrôle'         = $dateControle
    })
}

Write-Host "`n--- Résultat de conformité ---`n" -ForegroundColor Cyan
$resultats | Format-Table Poste, 'KB requises', 'KB manquantes', 'État', 'Date du contrôle' -AutoSize

foreach ($r in ($resultats | Where-Object { $_.'État' -eq "NON CONFORME" })) {
    Write-Host "$($r.Poste) : KB manquants -> $($r.'Liste des KB manquantes')  (contrôle du $($r.'Date du contrôle'))" -ForegroundColor Yellow
}

$resultats | Export-Csv -Path $cheminCSV -NoTypeInformation -Encoding Default -Delimiter ";"

$ok  = @($resultats | Where-Object { $_.'État' -eq "CONFORME" }).Count
$nok = @($resultats | Where-Object { $_.'État' -eq "NON CONFORME" }).Count
if (($ok + $nok) -gt 0) {
    $taux = [math]::Round(($ok / ($ok + $nok)) * 100, 2)
    Write-Host "`nTaux global de conformité : $taux % ($ok/$($ok + $nok) postes accessibles)" -ForegroundColor Green
    Write-AuditLog "Taux de conformité du parc : $taux %"
} else {
    Write-Host "`nTaux global de conformité : N/A (aucun poste accessible)" -ForegroundColor Red
    Write-AuditLog "Taux de conformité du parc : N/A"
}

Write-AuditLog "ComplianceReport.csv généré : $cheminCSV"
