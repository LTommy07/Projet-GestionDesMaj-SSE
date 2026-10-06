# ==================================================================================================
# Test-PatchCompliance.ps1 – Partie 4 : contrôle de conformité
# Rôle : compare les correctifs installés sur chaque poste avec la liste des correctifs obligatoires. Un poste est CONFORME uniquement si TOUS les KB requis sont installés.
# Entrées : computers.txt (NOM;IP) et required-patches.txt (un KB par ligne, ex. KB5066790)
# Sorties : ComplianceReport.csv (lu par New-SecurityReport.ps1 et Send-PatchAlert.ps1), tableau et taux global à l'écran, lignes dans Patch_Manager.log.
# États possibles : CONFORME, NON CONFORME, INACCESSIBLE.
# ==================================================================================================

# Dossier de travail et chemins des fichiers.
$Dossier = "C:\Users\local-admin\Desktop"
$fichierInventaire = Join-Path $Dossier "computers.txt"
$fichierRequis     = Join-Path $Dossier "required-patches.txt"
$cheminCSV         = Join-Path $Dossier "ComplianceReport.csv"
$cheminLog         = Join-Path $Dossier "Patch_Manager.log"

# Écrit une ligne horodatée dans le journal commun (Patch_Manager.log) et l'affiche à l'écran.
function Write-AuditLog {
    param([string]$Message)
    $ligne = "{0}; {1}" -f (Get-Date).ToString("dd/MM/yyyy HH:mm:ss"), $Message
    Add-Content -Path $cheminLog -Value $ligne -Encoding UTF8
    Write-Host $ligne
}

# Lecture de la liste des KB obligatoires : chaque ligne est nettoyée (espaces retirés, majuscules)
if (-not (Test-Path $fichierRequis)) { throw "Fichier introuvable : $fichierRequis" }
$requis = @(Get-Content -Path $fichierRequis -Encoding Default |
    ForEach-Object { $_.Trim().ToUpper() } |
    Where-Object { $_ -match '^KB\d+$' } | Sort-Object -Unique)
if ($requis.Count -eq 0) { throw "Aucun KB valide dans $fichierRequis" }

Write-AuditLog "Début du contrôle de conformité ($($requis.Count) KB requis)"

# Un seul horodatage pour tout le contrôle : tous les postes ont la même date et heure dans le CSV.
$dateControle = (Get-Date).ToString("dd/MM/yyyy HH:mm:ss")
$ordinateurs  = Get-Content -Path $fichierInventaire -Encoding Default
$resultats    = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($ligne in $ordinateurs) {
    if ([string]::IsNullOrWhiteSpace($ligne)) { continue }
    $nom, $ip = $ligne -split ";"
    $nom = $nom.Trim(); $ip = $ip.Trim()

    # $etat reste vide tant que le poste n'est pas jugé INACCESSIBLE.
    $etat = $null; $installes = @(); $manquants = @()

    # Même logique que Get-SystemInventory.ps1 : ping, puis commande distante. Un échec à l'un des deux niveaux donne l'état INACCESSIBLE.
    if (-not (Test-Connection -ComputerName $ip -Count 1 -Quiet)) {
        $etat = "INACCESSIBLE"
    } else {
        try {
            # Ne récupère que les identifiants KB installés, mis en majuscules pour que la comparaison avec la liste requise soit fiable.
            $installes = @(Invoke-Command -ComputerName $ip -ErrorAction Stop -ScriptBlock {
                (Get-HotFix).HotFixID
            } | ForEach-Object { "$_".ToUpper() })
        } catch {
            $etat = "INACCESSIBLE"
            Write-AuditLog "$nom; ERREUR WinRM; $($_.Exception.Message)"
        }
    }

    # Comparaison : manquants = KB requis qui ne figurent pas parmi les KB installés. CONFORME seulement si aucun KB ne manque.
    if (-not $etat) {
        $manquants = @($requis | Where-Object { $installes -notcontains $_ })
        $etat = if ($manquants.Count -eq 0) { "CONFORME" } else { "NON CONFORME" }
    }

    # Une ligne par poste. Les noms de colonnes sont ceux que lit New-SecurityReport.ps1 : ne pas les renommer. "-" pour un poste inaccessible.
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

# Affichage du tableau, puis, pour chaque poste non conforme, la liste précise des KB manquants avec la date du contrôle.
Write-Host "`n--- Résultat de conformité ---`n" -ForegroundColor Cyan
$resultats | Format-Table Poste, 'KB requises', 'KB manquantes', 'État', 'Date du contrôle' -AutoSize

foreach ($r in ($resultats | Where-Object { $_.'État' -eq "NON CONFORME" })) {
    Write-Host "$($r.Poste) : KB manquants -> $($r.'Liste des KB manquantes')  (contrôle du $($r.'Date du contrôle'))" -ForegroundColor Yellow
}

$resultats | Export-Csv -Path $cheminCSV -NoTypeInformation -Encoding Default -Delimiter ";"

# Taux global = postes conformes / (conformes + non conformes). Les INACCESSIBLES sont exclus du calcul, et on évite la division par zéro si aucun poste n'est accessible.
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
