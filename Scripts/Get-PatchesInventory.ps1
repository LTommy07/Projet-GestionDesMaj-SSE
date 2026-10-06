# ==================================================================================================
# Get-PatchesInventory.ps1 – Partie 3 : inventaire des correctifs
# Rôle    : liste les correctifs (KB) installés sur la machine locale puis sur chaque poste accessible du parc, et les regroupe dans un seul fichier.
# Entrée  : computers.txt (NOM;IP)
# Sortie  : Patches_Inventory.csv (trié par poste puis par date décroissante), résumé par machine à l'écran, lignes dans Patch_Manager.log.
# Principe : un poste éteint ou en erreur WinRM est journalisé puis ignoré, sans interrompre le script.
# ==================================================================================================

# Dossier de travail et chemins des fichiers.
$Dossier 	   = "C:\Users\local-admin\Desktop"
$fichierInventaire = Join-Path $Dossier "computers.txt"
$cheminCSV         = Join-Path $Dossier "Patches_Inventory.csv"
$cheminLog         = Join-Path $Dossier "Patch_Manager.log"

# Écrit une ligne horodatée "jj/MM/aaaa HH:mm:ss; message" dans le journal commun à tous les scripts (Add-Content ajoute à la suite sans effacer l'historique) et l'affiche aussi à l'écran.
function Write-AuditLog {
    param([string]$Message)
    $ligne = "{0}; {1}" -f (Get-Date).ToString("dd/MM/yyyy HH:mm:ss"), $Message
    Add-Content -Path $cheminLog -Value $ligne -Encoding UTF8
    Write-Host $ligne
}

Write-AuditLog "Début de l'inventaire des correctifs"

Write-Host "`n--- Correctifs de la machine locale ($env:COMPUTERNAME) ---`n" -ForegroundColor Cyan
# Correctifs de la machine locale. La date InstalledOn est lue dans un try/catch : sur certains KB,
# Windows ne sait pas la convertir. La date reste alors vide au lieu de bloquer le script.
Get-HotFix | ForEach-Object {
    $d = $null
    try { $d = $_.InstalledOn } catch { }
    [PSCustomObject]@{ HotFixID = $_.HotFixID; Description = $_.Description; InstalledOn = $d; InstalledBy = $_.InstalledBy }
} | Sort-Object InstalledOn -Descending | Format-Table -AutoSize

$ordinateurs = Get-Content -Path $fichierInventaire -Encoding Default
$tous = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($ligne in $ordinateurs) {
    if ([string]::IsNullOrWhiteSpace($ligne)) { continue }
    $nom, $ip = $ligne -split ";"
    $nom = $nom.Trim(); $ip = $ip.Trim()

    if (-not (Test-Connection -ComputerName $ip -Count 1 -Quiet)) {
        Write-AuditLog "$nom; Inaccessible (ignoré pour l'inventaire des correctifs)"
        continue
    }

    try {
        # Collecte distante via WinRM : le bloc s'exécute sur le poste distant. @( ) garantit un tableau même s'il n'y a qu'un seul résultat.
        $hotfixes = @(Invoke-Command -ComputerName $ip -ErrorAction Stop -ScriptBlock {
            Get-HotFix | ForEach-Object {
                $d = $null
                try { $d = $_.InstalledOn } catch { }
                [PSCustomObject]@{ HotFixID = $_.HotFixID; Description = $_.Description; InstalledOn = $d; InstalledBy = $_.InstalledBy }
            }
        })
        # Une ligne par correctif, avec le nom et l'IP du poste pour pouvoir tout regrouper dans un seul
        # fichier.
        foreach ($h in $hotfixes) {
            $tous.Add([PSCustomObject]@{
                Poste       = $nom
                IP          = $ip
                KB          = $h.HotFixID
                Description = $h.Description
                DateInstall = if ($h.InstalledOn) { [datetime]$h.InstalledOn } else { $null }
                InstallePar = $h.InstalledBy
            })
        }
        Write-AuditLog "$nom; $($hotfixes.Count) correctifs recensés"
    } catch {
        Write-AuditLog "$nom; ERREUR WinRM; $($_.Exception.Message)"
    }
}

# Tri : par poste (ordre alphabétique) puis par date d'installation décroissante, pour avoir le correctif le plus récent en premier.
$tries = $tous | Sort-Object @{ Expression = 'Poste'; Descending = $false },
                             @{ Expression = 'DateInstall'; Descending = $true }

# Renommage des colonnes selon le sujet (propriétés calculées @{n=nom; e=valeur}) et dates au format jj/MM/aaaa ("N/A" si la date est illisible).
$export = $tries | Select-Object Poste,
    @{ n = 'Adresse IP';          e = { $_.IP } },
    KB,
    Description,
    @{ n = "Date d'installation"; e = { if ($_.DateInstall) { $_.DateInstall.ToString("dd/MM/yyyy") } else { "N/A" } } },
    @{ n = 'Installé par';        e = { $_.InstallePar } }

$export | Export-Csv -Path $cheminCSV -NoTypeInformation -Encoding Default -Delimiter ";"

# Résumé par machine : Group-Object regroupe les lignes par poste. La liste étant déjà triée, le premier élément du groupe est le correctif le plus récent.
Write-Host "`n--- Résumé par machine ---`n" -ForegroundColor Cyan
$tries | Group-Object Poste | ForEach-Object {
    $dernier = $_.Group | Select-Object -First 1
    [PSCustomObject]@{
        Poste                 = $_.Name
        'Nombre de correctifs' = $_.Count
        'Date du plus récent'  = if ($dernier.DateInstall) { $dernier.DateInstall.ToString("dd/MM/yyyy") } else { "N/A" }
        'KB du plus récent'    = $dernier.KB
    }
} | Format-Table -AutoSize

Write-AuditLog "Inventaire des correctifs généré : $cheminCSV"
Write-Host "Fichier généré : $cheminCSV" -ForegroundColor Green
