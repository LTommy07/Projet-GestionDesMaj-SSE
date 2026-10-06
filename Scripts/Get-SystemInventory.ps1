# ==================================================================================================
# Get-SystemInventory.ps1 – Partie 2 : inventaire du parc
# Rôle : pour chaque poste, indique s'il est accessible puis, via PowerShell Remoting (WinRM), collecte ses caractéristiques système et son état de Patch Management.
# Entrée : computers.txt (NOM;IP)
# Sortie : tableau à l'écran + Inventaire.csv (lu ensuite par New-SecurityReport.ps1).
# Principe : un poste éteint ou en erreur WinRM n'arrête jamais le script ; l'état est simplement noté dans la colonne État.
# ==================================================================================================

$fichierInventaire = "C:\Users\local-admin\Desktop\computers.txt"
$cheminCSV = "C:\Users\local-admin\Desktop\Inventaire.csv"

# Liste qui cumule un objet par poste (plus efficace qu'un tableau agrandi avec +=).
$inventaireGlobal = [System.Collections.Generic.List[PSCustomObject]]::new()

# -Encoding Default : encodage ANSI de Windows, le même dans tous les scripts pour que les accents des CSV restent lisibles.
$ordinateurs = Get-Content -Path $fichierInventaire -Encoding Default

foreach ($ligne in $ordinateurs) {
    if ([string]::IsNullOrWhiteSpace($ligne)) { continue }

    $nom, $ip = $ligne -split ";"
    
    # Étape 1 : on teste la disponibilité AVANT toute commande distante, pour ne pas attendre un long délai d'expiration sur un poste éteint.
    if (Test-Connection -ComputerName $ip -Count 1 -Quiet) {
        try {
            # Étape 2 : collecte distante via WinRM. Le bloc entre accolades s'exécute SUR le poste distant et renvoie un seul objet. 
	    # -ErrorAction Stop transforme toute erreur en exception, interceptée par le catch plus bas.
            $donneesDistantes = Invoke-Command -ComputerName $ip -ErrorAction Stop -ScriptBlock {
                $cs   = Get-CimInstance -ClassName Win32_ComputerSystem
                $os   = Get-CimInstance -ClassName Win32_OperatingSystem
                $bios = Get-CimInstance -ClassName Win32_BIOS
                $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='C:'"
                
                $hotfixes  = Get-HotFix
                $wuService = Get-Service -Name wuauserv
                
                $ramGo  = if ($cs.TotalPhysicalMemory) { [math]::Round($cs.TotalPhysicalMemory / 1GB, 2) } else { 0 }
                $diskGo = if ($disk.FreeSpace) { [math]::Round($disk.FreeSpace / 1GB, 2) } else { 0 }
                $boot   = if ($os.LastBootUpTime) { $os.LastBootUpTime.ToString("dd/MM/yyyy") } else { "N/A" }
                
                $nbMaj = if ($hotfixes) { @($hotfixes).Count } else { 0 }
                $derniereMajDate = "N/A"
                
                if ($hotfixes) {
                    $validHotfixes = $hotfixes | Where-Object { $_.InstalledOn }
                    
                    if ($validHotfixes) {
                        $lastHotfix = $validHotfixes | Sort-Object InstalledOn -Descending | Select-Object -First 1
                        
                        if ($lastHotfix.InstalledOn -is [datetime]) {
                            $derniereMajDate = $lastHotfix.InstalledOn.ToString("dd/MM/yyyy")
                        } else {
                            $derniereMajDate = $lastHotfix.InstalledOn
                        }
                    }
                }

                # Objet renvoyé au poste d'administration ; ses propriétés sont réutilisées juste après pour remplir la ligne de l'inventaire.
                [PSCustomObject]@{
                    Modele          = $cs.Model
                    Bios            = $bios.SMBIOSBIOSVersion
                    OS_Edition      = $os.Caption
                    Architecture    = $os.OSArchitecture
                    DernierBoot     = $boot
                    RAM_Go          = $ramGo
                    EspaceDisque_Go = $diskGo
                    MAJ_Nombre      = $nbMaj
                    MAJ_Derniere    = $derniereMajDate
                    WU_Etat         = $wuService.Status
                }
            }

            # Poste accessible : on assemble la ligne de l'inventaire à partir des données distantes.
            $machine = [PSCustomObject]@{
                Poste               = $nom
                'Adresse IP'        = $ip
                Windows             = $donneesDistantes.OS_Edition
                Architecture        = $donneesDistantes.Architecture
                'Dernier démarrage' = $donneesDistantes.DernierBoot
                'Windows Update'    = $donneesDistantes.WU_Etat
                État                = "Accessible"
                Modele              = $donneesDistantes.Modele
                VersionBios         = $donneesDistantes.Bios
                'RAM (Go)'          = $donneesDistantes.RAM_Go
                'Disque C Libre'    = $donneesDistantes.EspaceDisque_Go
                'Dernière MAJ'      = $donneesDistantes.MAJ_Derniere
                'Nombre MAJ'        = $donneesDistantes.MAJ_Nombre
            }

        } catch {
            # Poste joignable au ping mais WinRM en échec : le message d'erreur est conservé dans la colonne État et le script continue.
            $machine = [PSCustomObject]@{
                Poste               = $nom
                'Adresse IP'        = $ip
                Windows             = ""
                Architecture        = ""
                'Dernier démarrage' = ""
                'Windows Update'    = ""
                État                = "Erreur WinRM : $($_.Exception.Message)"
                Modele              = ""
                VersionBios         = ""
                'RAM (Go)'          = ""
                'Disque C Libre'    = ""
                'Dernière MAJ'      = ""
                'Nombre MAJ'        = ""
            }
        }

    } else {
        # Poste qui ne répond pas au ping : état Inaccessible, les autres colonnes restent vides.
        $machine = [PSCustomObject]@{
            Poste               = $nom
            'Adresse IP'        = $ip
            Windows             = ""
            Architecture        = ""
            'Dernier démarrage' = ""
            'Windows Update'    = ""
            État                = "Inaccessible"
            Modele              = ""
            VersionBios         = ""
            'RAM (Go)'          = ""
            'Disque C Libre'    = ""
            'Dernière MAJ'      = ""
            'Nombre MAJ'        = ""
        }
    }
    
    # Ajoute la ligne du poste (quel que soit son état) à l'inventaire global.
    $inventaireGlobal.Add($machine)
}

Write-Host "`n--- Inventaire du Parc ---`n" -ForegroundColor Cyan

# Colonnes du tableau affiché à l'écran (largeur fixe pour ne pas tronquer le message d'état). Le CSV, lui, contient toutes les colonnes.
$formatColonnes = @(
    @{ Label = "Poste"; Expression = { $_.Poste }; Width = 15 }
    @{ Label = "Adresse IP"; Expression = { $_.'Adresse IP' }; Width = 18 }
    @{ Label = "Windows"; Expression = { $_.Windows }; Width = 32 }
    @{ Label = "Architecture"; Expression = { $_.Architecture }; Width = 14 }
    @{ Label = "Dernier démarrage"; Expression = { $_.'Dernier démarrage' }; Width = 19 }
    @{ Label = "Windows Update"; Expression = { $_.'Windows Update' }; Width = 16 }
    @{ Label = "État"; Expression = { $_.État }; Width = 50 }
)

$inventaireGlobal | Format-Table $formatColonnes

$inventaireGlobal | Export-Csv -Path $cheminCSV -NoTypeInformation -Encoding Default -Delimiter ";"

Write-Host "Inventaire terminé. Fichier généré : $cheminCSV" -ForegroundColor Green
