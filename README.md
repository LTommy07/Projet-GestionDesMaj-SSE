# Système de gestion des mises à jour en PowerShell

Solution d'automatisation de **gestion et de contrôle des correctifs Windows** via PowerShell Remoting (WinRM). Ce projet permet d'auditer un parc informatique à distance depuis un poste central, de vérifier la conformité des correctifs (KB), de générer un rapport HTML d'audit et de notifier l'administrateur par e-mail uniquement en cas d'anomalie.

### Contexte académique
Projet réalisé dans le cadre du module **Sécurité des Systèmes d'exploitation (EFREI)**.

| Étudiant | Modules pris en charge |
|---|---|
| Ismaël RADOUANE | Partie 1 (Connectivité), 2 (Inventaire OS), 6 (Rapport HTML/Log), 8 (Menu/Audit complet) |
| Tommy LIM | Partie 3 (Inventaire KB), 4 (Conformité), 7 (Alerte Mail) |

## Architecture du dépôt

```
.
├── Config/
│   ├── computers.txt            # Parc : une machine par ligne, format NOM;IP
│   └── required-patches.txt     # KB obligatoires : un par ligne (ex : KB5066790)
├── Scripts/
│   ├── Invoke-PatchManager.ps1  # Script maître : menu qui lance tout l'audit
│   ├── Check-Connectivity.ps1   # Partie 1 – test de connectivité (ping)
│   ├── Get-SystemInventory.ps1  # Partie 2 – inventaire système  -> Inventaire.csv
│   ├── Get-PatchesInventory.ps1 # Partie 3 – inventaire des KB   -> Patches_Inventory.csv
│   ├── Test-PatchCompliance.ps1 # Partie 4 – conformité          -> ComplianceReport.csv
│   ├── New-SecurityReport.ps1   # Partie 6 – rapport + journal   -> Rapport_Securite.html
│   └── Send-PatchAlert.ps1      # Partie 7 – alerte e-mail
└── README.md
```

Chaque script produit le fichier lu par le suivant. De plus, `Inventaire.csv` et `ComplianceReport.csv` alimentent le rapport HTML, lui-même joint à l'e-mail. Tous écrivent dans le journal `Patch_Manager.log`.

## Environnement de test

Trois machines Windows 10 sous VMware (réseau NAT, DHCP désactivé), compte local `local-admin` :

| Machine | Rôle | IP |
|---|---|---|
| PC-ADMIN | Poste d'administration | 192.168.10.10 |
| PC01 | Poste supervisé | 192.168.10.11 |
| PC02 | Poste supervisé | 192.168.10.12 |

## Installation

Les scripts utilisent le chemin `C:\Users\local-admin\Desktop`. Sur PC-ADMIN, tous les scripts du dossier `Scripts/`, `computers.txt` et `required-patches.txt` doivent être copier sur le Bureau de `local-admin`.

```powershell
cd C:\Users\local-admin\Desktop
Get-ChildItem *.ps1 | Unblock-File
```

## Configuration

**1. Autoriser l'exécution des scripts** (PC-ADMIN)

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

**2. Activer PowerShell Remoting / WinRM**

Sur **PC01 et PC02**, en PowerShell administrateur :

```powershell
Get-NetConnectionProfile | Set-NetConnectionProfile -NetworkCategory Private
Enable-PSRemoting -Force
Enable-NetFirewallRule -Name "CoreNet-Diag-ICMP4-EchoRequest-In"   # autorise le ping
```

Sur **PC-ADMIN** :

```powershell
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "192.168.10.11,192.168.10.12" -Force
Test-WSMan 192.168.10.11
Invoke-Command -ComputerName 192.168.10.11,192.168.10.12 -ScriptBlock { hostname }
```

**3. Configurer l'envoi d'e-mail (`smtp.cred.xml`)**

Le mot de passe SMTP n'est jamais écrit dans les scripts. Il est lu dans `smtp.cred.xml`, à créer une seule fois, sur PC-ADMIN, avec le compte qui lancera les scripts :

```powershell
Get-Credential | Export-Clixml C:\Users\local-admin\Desktop\smtp.cred.xml
```

Saisir l'identifiant et le mot de passe du compte SMTP. Nous avons utilisé **Ethereal Email** (https://ethereal.email, compte de test gratuit). Le serveur et le port sont les paramètres `-SmtpServer` et `-Port` de `Send-PatchAlert.ps1` (valeurs par défaut en haut du script), à adapter au serveur utilisé : pour Ethereal, `smtp.ethereal.email` et `587`.

## Utilisation

### Audit complet avec le script maître

**Avant le premier lancement, ouvrir `Invoke-PatchManager.ps1` et modifier en haut du fichier** les deux lignes suivantes avec l'adresse du compte SMTP (expéditeur) et celle de l'administrateur qui doit recevoir l'alerte (destinataire) :

```powershell
$emailExpediteur   = "expediteur@exemple.com"
$emailDestinataire = "administrateur@exemple.com"
```

Puis :

```powershell
cd C:\Users\local-admin\Desktop
.\Invoke-PatchManager.ps1
```

| Option | Action |
|---|---|
| 1 | Audit complet (toutes les étapes ci-dessous, dans l'ordre) |
| 2 | Connectivité (partie 1) |
| 3 | Inventaire système (partie 2) |
| 4 | Inventaire des correctifs (partie 3) |
| 5 | Conformité (partie 4) |
| 6 | Rapport HTML + alerte e-mail (parties 6 et 7) |
| Q | Quitter |

L'option 6 suppose que `Inventaire.csv` et `ComplianceReport.csv` existent déjà (lancer d'abord les options 3 et 5, ou l'option 1).

### Scripts un par un

```powershell
.\Get-SystemInventory.ps1
.\Get-PatchesInventory.ps1
.\Test-PatchCompliance.ps1
.\New-SecurityReport.ps1
.\Send-PatchAlert.ps1 -From "expediteur@exemple.com" -To "administrateur@exemple.com" -SmtpServer smtp.ethereal.email -Port 587
```

L'e-mail n'est envoyé que s'il existe au moins un poste **NON CONFORME** ou **INACCESSIBLE**, sinon le script le note dans le journal et se termine sans rien envoyer. Pour provoquer une anomalie lors d'un test, on peut ajouter un KB inexistant (ex : `KB9999999`) dans `required-patches.txt`, ou éteindre un poste.
