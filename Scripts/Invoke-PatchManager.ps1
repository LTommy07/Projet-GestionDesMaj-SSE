# ==================================================================================================
# Invoke-PatchManager.ps1 – Script maître : menu interactif du Patch Management
# Rôle : point d'entrée unique de la solution. Affiche un menu et lance, selon le choix, un script ou toute la chaîne d'audit.
# Prérequis : tous les scripts du projet, computers.txt et required-patches.txt doivent se trouver dans le dossier ci-dessous.
# Option 1 : audit complet (connectivité, inventaire système, inventaire des correctifs, conformité, rapport HTML, alerte). Options 2 à 6 : une seule étape.
# ==================================================================================================

# Paramètres : dossier des scripts et adresses utilisées pour l'alerte e-mail (aucun mot de passe ici).
$dossierBureau = "C:\Users\local-admin\Desktop"
$emailExpediteur = "white.sunshine.thunder@gmail.com"
$emailDestinataire = "white.sunshine.thunder@gmail.com"

# Lance un script du dossier à partir de son nom. Vérifie d'abord qu'il existe (sinon message d'erreur et le menu continue).
# Le commutateur -EstAlerte ajoute l'expéditeur et le destinataire, nécessaires seulement pour Send-PatchAlert.ps1.
function Invoke-Script {
    param(
        [string]$NomScript,
        [switch]$EstAlerte
    )
    $chemin = Join-Path -Path $dossierBureau -ChildPath $NomScript

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

# Boucle du menu : elle tourne jusqu'à ce que l'utilisateur choisisse Q.
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

    # Option 1 : chaîne complète, dans l'ordre des dépendances (chaque script produit le fichier lu par le suivant). 
    # Options 2 à 5 : une étape.
    # Option 6 : rapport + alerte, qui suppose que Inventaire.csv et ComplianceReport.csv existent déjà.
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
        "Q" { $quitter = $true }
        "q" { $quitter = $true }
        default { Write-Host "`nChoix invalide, veuillez réessayer." -ForegroundColor Yellow }
    }

    if (-not $quitter) {
        Write-Host "`nAppuyez sur Entrée pour revenir au menu..." -ForegroundColor DarkGray
        $null = Read-Host
    }
}
