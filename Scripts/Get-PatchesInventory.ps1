$Dossier 	   = "C:\Users\local-admin\Desktop"
$fichierInventaire = Join-Path $Dossier "computers.txt"
$cheminCSV         = Join-Path $Dossier "Patches_Inventory.csv"
$cheminLog         = Join-Path $Dossier "Patch_Manager.log"

function Write-AuditLog {
    param([string]$Message)
    $ligne = "{0}; {1}" -f (Get-Date).ToString("dd/MM/yyyy HH:mm:ss"), $Message
    Add-Content -Path $cheminLog -Value $ligne -Encoding UTF8
    Write-Host $ligne
}

Write-AuditLog "Début de l'inventaire des correctifs"

Write-Host "`n--- Correctifs de la machine locale ($env:COMPUTERNAME) ---`n" -ForegroundColor Cyan
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
        $hotfixes = @(Invoke-Command -ComputerName $ip -ErrorAction Stop -ScriptBlock {
            Get-HotFix | ForEach-Object {
                $d = $null
                try { $d = $_.InstalledOn } catch { }
                [PSCustomObject]@{ HotFixID = $_.HotFixID; Description = $_.Description; InstalledOn = $d; InstalledBy = $_.InstalledBy }
            }
        })
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

$tries = $tous | Sort-Object @{ Expression = 'Poste'; Descending = $false },
                             @{ Expression = 'DateInstall'; Descending = $true }

$export = $tries | Select-Object Poste,
    @{ n = 'Adresse IP';          e = { $_.IP } },
    KB,
    Description,
    @{ n = "Date d'installation"; e = { if ($_.DateInstall) { $_.DateInstall.ToString("dd/MM/yyyy") } else { "N/A" } } },
    @{ n = 'Installé par';        e = { $_.InstallePar } }

$export | Export-Csv -Path $cheminCSV -NoTypeInformation -Encoding Default -Delimiter ";"

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
