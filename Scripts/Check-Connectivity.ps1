# ==================================================================================================
# Check-Connectivity.ps1 – Partie 1 : test de connectivité du parc
# Rôle    : affiche pour chaque poste son nom, son adresse IP et son état (ping).
# Entrée  : computers.txt (une machine par ligne, format NOM;IP, ex. PC01;192.168.10.11).
# Sortie  : affichage à l'écran uniquement.
# ==================================================================================================

$ordinateurs = Get-Content -Path "C:\Users\local-admin\Desktop\computers.txt"

foreach ($ligne in $ordinateurs) {
    $nom, $ip = $ligne -split ";"
    
    if (Test-Connection -ComputerName $ip -Count 1 -Quiet) {
        $etat = "Accessible"
    } else {
        $etat = "Inaccessible"
    }
    
    Write-Host "Nom : $nom | IP : $ip | État : $etat"
}
