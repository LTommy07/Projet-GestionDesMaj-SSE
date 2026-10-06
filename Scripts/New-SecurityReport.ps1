# ==================================================================================================
# New-SecurityReport.ps1 – Partie 6 : rapport de sécurité HTML et journal
# Rôle : fusionne l'inventaire système et le contrôle de conformité en un rapport HTML pour
# l'administrateur (synthèse globale, postes à traiter, détail par poste) et alimente le journal.
# Entrées : Inventaire.csv (partie 2) et ComplianceReport.csv (partie 4) : ces scripts doivent donc être lancés avant.
# Sorties : Rapport_Securite.html (joint au mail de la partie 7) et lignes dans Patch_Manager.log.
# ==================================================================================================

# Dossier de travail et chemins des fichiers d'entrée, de sortie et du journal.
$dossierBureau     = "C:\Users\local-admin\Desktop"
$cheminInventaire  = "$dossierBureau\Inventaire.csv"
$cheminConformite  = "$dossierBureau\ComplianceReport.csv"
$cheminRapportHTML = "$dossierBureau\Rapport_Securite.html"
$cheminLog         = "$dossierBureau\Patch_Manager.log"

# Écrit une ligne horodatée dans le journal commun (Add-Content ajoute à la suite sans effacer l'historique) et l'affiche à l'écran.
function Write-AuditLog {
    param (
        [string]$Message
    )
    $horodatage = (Get-Date).ToString("dd/MM/yyyy HH:mm:ss")
    $ligneLog = "$horodatage; $Message"
    Add-Content -Path $cheminLog -Value $ligneLog -Encoding UTF8
    Write-Host $ligneLog
}

Write-AuditLog "Début de l'audit"

# Le rapport a besoin des deux CSV : s'il en manque un, l'erreur est journalisée et le script s'arrête.
if (!(Test-Path $cheminInventaire) -or !(Test-Path $cheminConformite)) {
    Write-AuditLog "ERREUR; Fichiers CSV introuvables. Le rapport ne peut pas être généré."
    Exit
}

$inventaire = Import-Csv -Path $cheminInventaire -Delimiter ";" -Encoding Default
$conformite = Import-Csv -Path $cheminConformite -Delimiter ";" -Encoding Default

$donneesRapport = [System.Collections.Generic.List[PSCustomObject]]::new()

# Pour chaque poste de l'inventaire : on cherche sa ligne de conformité (même nom de poste) et on fusionne les deux sources en un seul objet.
foreach ($machine in $inventaire) {
    $nom = $machine.Poste
    $etatAccessibilite = $machine.État

    if ($etatAccessibilite -eq "Accessible") {
        Write-AuditLog "$nom; Accessible"
    } else {
        Write-AuditLog "$nom; $etatAccessibilite"
    }

    $donneesConformite = $conformite | Where-Object { $_.Poste -eq $nom }
    
    if ($donneesConformite) {
        $etatConformite = $donneesConformite.État.Trim()
        
        if ($etatConformite -match "NON CONFORME") {
            Write-AuditLog "$nom; Non conforme; $($donneesConformite.'Liste des KB manquantes')"
        } elseif ($etatConformite -match "CONFORME") {
            Write-AuditLog "$nom; Conforme"
        }

        $objetCombine = [PSCustomObject]@{
            Poste                  = $nom
            'Adresse IP'           = $machine.'Adresse IP'
            'État accessibilité'   = $etatAccessibilite
            Windows                = $machine.Windows
            'Dernier démarrage'    = $machine.'Dernier démarrage'
            'Windows Update'       = $machine.'Windows Update'
            'Correctifs requis'    = $donneesConformite.'KB requises'
            'Correctifs manquants' = $donneesConformite.'KB manquantes'
            'KB manquantes'        = $donneesConformite.'Liste des KB manquantes'
            Conformité             = $etatConformite
            'Date contrôle'        = $donneesConformite.'Date du contrôle'
        }
    } else {
        # Poste absent du fichier de conformité : état INCONNU.
        $objetCombine = [PSCustomObject]@{
            Poste                  = $nom
            'Adresse IP'           = $machine.'Adresse IP'
            'État accessibilité'   = $etatAccessibilite
            Windows                = $machine.Windows
            'Dernier démarrage'    = $machine.'Dernier démarrage'
            'Windows Update'       = $machine.'Windows Update'
            'Correctifs requis'    = "N/A"
            'Correctifs manquants' = "N/A"
            'KB manquantes'        = "N/A"
            Conformité             = "INCONNU"
            'Date contrôle'        = "N/A"
        }
    }
    
    $donneesRapport.Add($objetCombine)
}

# Calculs de la synthèse globale.
$totalPostes     = @($donneesRapport).Count
$accessibles     = @($donneesRapport | Where-Object { $_.'État accessibilité' -match "Accessible" }).Count
$inaccessibles   = $totalPostes - $accessibles

$conformes       = @($donneesRapport | Where-Object { $_.Conformité -match "CONFORME" -and $_.Conformité -notmatch "NON" }).Count
$nonConformes    = @($donneesRapport | Where-Object { $_.Conformité -match "NON CONFORME" }).Count

# Somme des KB manquants : seules les valeurs numériques sont additionnées ("-" et "N/A" sont ignorés).
$totalKbManquant = 0
$donneesRapport | Where-Object { $_.'Correctifs manquants' -match '\d+' } | ForEach-Object { 
    $totalKbManquant += [int]$_.'Correctifs manquants' 
}

# Taux de conformité en %, arrondi à 2 décimales ; la division est évitée s'il n'y a aucun poste accessible.
$tauxConformite = 0
if ($accessibles -gt 0) {
    $tauxConformite = [math]::Round(($conformes / $accessibles) * 100, 2)
}

# Postes nécessitant une intervention : tous ceux qui ne sont pas CONFORME (non conformes, inaccessibles, inconnus).
$postesIntervention = @($donneesRapport | Where-Object { $_.Conformité -notmatch "CONFORME" -or $_.Conformité -match "NON" })

# Feuille de style CSS intégrée au rapport (couleurs, tableaux, encadré de synthèse).
$head = @"
<style>
    body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 30px; background-color: #f8f9fa; color: #333; }
    h1 { color: #2c3e50; border-bottom: 2px solid #3498db; padding-bottom: 10px; }
    h2 { color: #34495e; margin-top: 30px; }
    table { border-collapse: collapse; width: 100%; margin-bottom: 30px; background-color: #fff; box-shadow: 0 2px 5px rgba(0,0,0,0.1); }
    th, td { border: 1px solid #dee2e6; padding: 12px; text-align: left; }
    th { background-color: #343a40; color: white; }
    tr:nth-child(even) { background-color: #f2f2f2; }
    .warning { color: #dc3545; font-weight: bold; }
    .success { color: #28a745; font-weight: bold; }
    .synthese-box { border: 1px solid #ced4da; padding: 20px; background-color: #ffffff; width: 400px; border-radius: 5px; box-shadow: 0 2px 5px rgba(0,0,0,0.1); }
    .synthese-box ul { list-style-type: none; padding: 0; margin: 0; }
    .synthese-box li { margin-bottom: 10px; font-size: 1.1em; }
</style>
"@

# Construction du corps HTML : titre, puis trois sections (synthèse globale, postes à traiter, détail complet).
$htmlBody = "<h1>Rapport de sécurité - Patch management</h1>"
$htmlBody += "<p>Généré le : $((Get-Date).ToString('dd/MM/yyyy à HH:mm:ss'))</p>"

$htmlBody += "<h2>1. Synthèse globale du parc</h2>"
$htmlBody += "<div class='synthese-box'><ul>"
$htmlBody += "<li><b>Nombre total de postes :</b> $totalPostes</li>"
$htmlBody += "<li><b>Postes accessibles :</b> $accessibles</li>"
$htmlBody += "<li><b>Postes inaccessibles :</b> $inaccessibles</li>"
$htmlBody += "<li><b class='success'>Postes conformes :</b> $conformes</li>"
$htmlBody += "<li><b class='warning'>Postes non conformes :</b> $nonConformes</li>"
$htmlBody += "<li><b>Total correctifs manquants :</b> $totalKbManquant</li>"
$htmlBody += "<li><b>Taux de conformité :</b> $tauxConformite %</li>"
$htmlBody += "</ul></div>"

$htmlBody += "<h2>2. Postes nécessitant une intervention</h2>"
if ($postesIntervention.Count -gt 0) {
    $htmlFragmentIntervention = $postesIntervention | Select-Object Poste, 'Adresse IP', Conformité, 'KB manquantes' | ConvertTo-Html -Fragment
    $htmlBody += $htmlFragmentIntervention -replace "<td>NON CONFORME</td>", "<td class='warning'>NON CONFORME</td>" -replace "<td>INACCESSIBLE</td>", "<td class='warning'>INACCESSIBLE</td>"
} else {
    $htmlBody += "<p class='success'>Aucune intervention requise. Tous les postes accessibles sont conformes.</p>"
}

$htmlBody += "<h2>3. Détail complet par poste</h2>"
$htmlFragmentDetail = $donneesRapport | ConvertTo-Html -Fragment
$htmlBody += $htmlFragmentDetail -replace "<td>CONFORME</td>", "<td class='success'>CONFORME</td>" -replace "<td>NON CONFORME</td>", "<td class='warning'>NON CONFORME</td>"

# Assemble la page complète (CSS + corps) et l'écrit en UTF-8.
ConvertTo-Html -Head $head -Body $htmlBody | Out-File $cheminRapportHTML -Encoding UTF8

Write-AuditLog "Rapport généré"
Write-AuditLog "Fin de l'audit"
Write-Host "`nLe rapport HTML a été généré avec succès dans : $cheminRapportHTML" -ForegroundColor Green
