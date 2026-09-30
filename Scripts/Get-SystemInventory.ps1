$fichierInventaire = "C:\Users\local-admin\Desktop\computers.txt"
$cheminCSV = "C:\Users\local-admin\Desktop\Inventaire.csv"

$inventaireGlobal = [System.Collections.Generic.List[PSCustomObject]]::new()

$ordinateurs = Get-Content -Path $fichierInventaire -Encoding Default

foreach ($ligne in $ordinateurs) {
    if ([string]::IsNullOrWhiteSpace($ligne)) { continue }

    $nom, $ip = $ligne -split ";"
    
    if (Test-Connection -ComputerName $ip -Count 1 -Quiet) {
        try {
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
    
    $inventaireGlobal.Add($machine)
}

Write-Host "`n--- Inventaire du Parc ---`n" -ForegroundColor Cyan

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