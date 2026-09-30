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