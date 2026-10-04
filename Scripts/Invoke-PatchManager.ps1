$dossierBureau = "C:\Users\local-admin\Desktop"
$emailExpediteur = "white.sunshine.thunder@gmail.com"
$emailDestinataire = "white.sunshine.thunder@gmail.com"

function Invoke-Script {
    param(
        [string]$NomScript, 
        [switch]$EstAlerte
    )
    $chemin = Join-Path -Path $dossierBureau -ChildPath$NomScript
    
    if (Test-Path $chemin) {
        Write-Host "`n[+] Exécution de $NomScript..." -ForegroundColor Yellow
        if ($EstAlerte) {
            & $chemin -From $emailExpediteur -To $emailDestinataire
        } else {
            & $chemin
        }
    } else {
        Write-Host "ERREUR : Le fichier $NomScript est introuvable sur le bureau." -ForegroundColor Red
    }
}

$quitter = $false

while (-not $quitter) {
    Clear-Host
    Write-Host "=====================================================" -ForegroundColor Cyan
    Write-Host "      SYSTÈME DE PATCH MANAGEMENT CENTRALISÉ         " -ForegroundColor White
    Write-Host "=====================================================" -ForegroundColor Cyan
    Write-Host "1. Lancer l'audit complet du parc (Toutes les étapes)" -ForegroundColor Green
    Write-Host "-----------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "2. Tester uniquement la connectivité (Partie 1)"
    Write-Host "3. Lancer l'inventaire système (Partie 2)"
    Write-Host "4. Lancer l'inventaire des correctifs (Partie 3)"
    Write-Host "5. Vérifier la conformité (Partie 4)"
    Write-Host "6. Générer le rapport HTML et alerter (Parties 6 & 7)"
    Write-Host "-----------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "Q. Quitter" -ForegroundColor Red
    Write-Host "=====================================================" -ForegroundColor Cyan
    
    $choix = Read-Host "Entrez votre choix (1-6 ou Q)"
    
    switch ($choix) {
        "1" { 
            Invoke-Script "Check-Connectivity.ps1"
            Invoke-Script "Get-SystemInventory.ps1"
            Invoke-Script "Get-PatchesInventory.ps1"
            Invoke-Script "Test-PatchCompliance.ps1"
            Invoke-Script "New-SecurityReport.ps1"
            Invoke-Script "Send-PatchAlert.ps1" -EstAlerte
            Write-Host "`n>>> Audit complet terminé." -ForegroundColor Green
        }
        "2" { Invoke-Script "Check-Connectivity.ps1" }
        "3" { Invoke-Script "Get-SystemInventory.ps1" }
        "4" { Invoke-Script "Get-PatchesInventory.ps1" }
        "5" { Invoke-Script "Test-PatchCompliance.ps1" }
        "6" { 
            Invoke-Script "New-SecurityReport.ps1" 
            Invoke-Script "Send-PatchAlert.ps1" -EstAlerte
        }
        "Q" { $quitter =$true }
        "q" { $quitter =$true }
        default { Write-Host "`nChoix invalide, veuillez réessayer." -ForegroundColor Yellow }
    }
    
    if (-not $quitter) {
        Write-Host "`nAppuyez sur Entrée pour revenir au menu..." -ForegroundColor DarkGray
        $null = Read-Host
    }
}
