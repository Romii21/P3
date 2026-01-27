<#
.SYNOPSIS
    Script de déploiement AD EcoTech - Version Finale V7
.DESCRIPTION
    - Structure : ECOTECH > BDX > UX/RX > Départements > Services
    - Users : Import CSV, Nomenclature stricte, Groupes par Fonction.
    - Managers : Option dédiée pour lier les comptes.
    - Logs : Console épurée (résumé), Fichier détaillé.
#>

# =============================================================================
# 1. CONFIGURATION
# =============================================================================

$isDryRun   = $true
$DomainDN   = "DC=ecotech,DC=local"
$RootName   = "ECOTECH"
$SiteName   = "BDX"
# Log : Date + Heure pour ne pas écraser les logs précédents
$LogFile    = "C:\Logs\EcoTech_Deploy_$(Get-Date -Format 'yyyyMMdd_HHmm').log"
$CsvPath    = "$PSScriptRoot\Fiche_personnels.csv"
$DefaultPwd = ConvertTo-SecureString "EcoTech2026!" -AsPlainText -Force

# Mapping Départements (Nom CSV -> Code OU)
$DeptMap = @{
    "directiondesressourceshumaines" = "D01"
    "financeetcomptabilite"          = "D02"
    "servicecommercial"              = "D03"
    "direction"                      = "D04"
    "developpement"                  = "D05"
    "communication"                  = "D06"
    "dsi"                            = "D07"
}

# =============================================================================
# 2. FONCTIONS OUTILS
# =============================================================================

function Write-Log {
    param(
        [string]$Message, 
        [string]$Level="INFO", 
        [switch]$ConsoleOutput = $true # Par défaut, on affiche. Si $false, log fichier uniquement.
    )
    
    $LogDir = Split-Path $LogFile -Parent
    if (!(Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }
    
    $Time = Get-Date -Format "HH:mm:ss"
    $Line = "[$Time] [$Level] $Message"
    
    # 1. Écriture Fichier (Toujours)
    Add-Content -Path $LogFile -Value $Line
    
    # 2. Affichage Console (Seulement si demandé)
    if ($ConsoleOutput) {
        $Color = switch ($Level) { "SUCCESS" {"Green"} "ERROR" {"Red"} "WARN" {"Yellow"} default {"Cyan"} }
        Write-Host $Line -ForegroundColor $Color
    }
}

function Get-CleanString {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return "" }
    $Text = $Text.ToLower().Normalize([System.Text.NormalizationForm]::FormD) -replace '\p{Mn}', ''
    return $Text -replace '[^a-z0-9]', ''
}

function Get-FormatPhone {
    param([string]$Phone)
    $Digits = $Phone -replace '[^0-9]', ''
    if ($Digits.Length -eq 10 -and ($Digits.StartsWith("06") -or $Digits.StartsWith("07"))) {
        return "+33 " + $Digits.Substring(1)
    }
    return $Phone
}

function Get-CalculatedLogin {
    param($Prenom, $Nom)
    $Prenom = ($Prenom -as [string]).Trim()
    $Nom    = ($Nom -as [string]).Trim()
    if ($Prenom.Length -ge 2) { $P2 = $Prenom.Substring(0,2) } else { $P2 = $Prenom }
    return Get-CleanString ($P2 + $Nom)
}

# =============================================================================
# 3. FONCTIONS MÉTIER
# =============================================================================

function New-InfraStructure {
    Write-Log "--- DÉBUT INFRASTRUCTURE ---"
    
    # 1. CRÉATION RACINE (ECOTECH)
    # On vérifie d'abord si elle existe à la racine du domaine
    if (!(Get-ADOrganizationalUnit -Filter "Name -eq '$RootName'" -SearchBase $DomainDN -ErrorAction SilentlyContinue)) {
        if ($isDryRun) { Write-Log "SIMULATION : Création Racine $RootName" "WARN" }
        else {
            try {
                New-ADOrganizationalUnit -Name $RootName -Path $DomainDN -ProtectedFromAccidentalDeletion $true
                Write-Log "Racine $RootName créée" "SUCCESS"
            } catch {
                Write-Log "ERREUR CRITIQUE création Racine : $_" "ERROR"
                return # On arrête tout si la racine ne peut pas être créée
            }
        }
    }

    # 2. CRÉATION SITE (BDX)
    # On vérifie dans la racine ECOTECH
    $PathRoot = "OU=$RootName,$DomainDN"
    if (!(Get-ADOrganizationalUnit -Filter "Name -eq '$SiteName'" -SearchBase $PathRoot -ErrorAction SilentlyContinue)) {
        if ($isDryRun) { Write-Log "SIMULATION : Création Site $SiteName" "WARN" }
        else {
            try {
                New-ADOrganizationalUnit -Name $SiteName -Path $PathRoot -ProtectedFromAccidentalDeletion $true
                Write-Log "Site $SiteName créé" "SUCCESS"
            } catch {
                Write-Log "ERREUR CRITIQUE création Site : $_" "ERROR"
                return
            }
        }
    }

    # 3. CRÉATION TYPES (GX, UX, RX, WX)
    $PathSite = "OU=$SiteName,$PathRoot"
    $OUs = @("GX", "UX", "RX", "WX")

    foreach ($OU in $OUs) {
        # On construit le chemin complet cible
        if (!(Get-ADOrganizationalUnit -Filter "Name -eq '$OU'" -SearchBase $PathSite -ErrorAction SilentlyContinue)) {
             if ($isDryRun) { Write-Log "SIMULATION : Création OU $OU" "WARN" }
             else { 
                try {
                    New-ADOrganizationalUnit -Name $OU -Path $PathSite -ProtectedFromAccidentalDeletion $true
                    Write-Log "OU $OU créée" "SUCCESS"
                } catch {
                    Write-Log "Erreur création $OU : $_" "ERROR"
                }
             }
        }
    }
    
    # 4. CRÉATION DÉPARTEMENTS (D01...D07)
    foreach ($Parent in @("UX", "RX")) {
        $PathParent = "OU=$Parent,$PathSite"
        foreach ($Code in $DeptMap.Values) {
            if (!(Get-ADOrganizationalUnit -Filter "Name -eq '$Code'" -SearchBase $PathParent -ErrorAction SilentlyContinue)) {
                if ($isDryRun) { Write-Log "SIMULATION : Création $Code dans $Parent" "WARN" }
                else { 
                    try {
                        New-ADOrganizationalUnit -Name $Code -Path $PathParent -ProtectedFromAccidentalDeletion $true
                        Write-Log "$Code dans $Parent créé" "SUCCESS"
                    } catch {
                        Write-Log "Erreur création $Code : $_" "ERROR"
                    }
                }
            }
        }
    }
}

function Sync-Users {
    Write-Log "--- DÉBUT SYNCHRO UTILISATEURS ---"
    if (!(Test-Path $CsvPath)) { Write-Log "CSV introuvable !" "ERROR"; return }
    
    try { $Users = Import-Csv -Path $CsvPath -Delimiter ";" -Encoding UTF8 } catch { Write-Log "Erreur Lecture CSV" "ERROR"; return }
    
    $CountOK = 0; $CountKO = 0; $CountSkip = 0
    Write-Host "Traitement des utilisateurs en cours... (Voir logs détaillés dans fichier)" -ForegroundColor Cyan

    foreach ($Row in $Users) {
        $Prenom = ($Row.Prenom -as [string]).Trim()
        $Nom    = ($Row.Nom -as [string]).Trim()
        if ([string]::IsNullOrWhiteSpace($Nom)) { continue }

        # 1. Calcul ID & OU
        $IdBase   = Get-CalculatedLogin $Prenom $Nom
        $DeptClean = Get-CleanString ($Row.Departement)
        $DeptCode  = $DeptMap[$DeptClean]
        
        if (-not $DeptCode) { 
            Write-Log "Dept Inconnu : $($Row.Departement) pour $Nom" "WARN" -ConsoleOutput $false
            $CountKO++; continue 
        }

        # 2. Gestion SERVICE (Sous-OU)
        $ServiceClean = ($Row.Service -as [string]).Trim()
        # Chemin Base : UX > Dxx
        $ParentPath = "OU=$DeptCode,OU=UX,OU=$SiteName,OU=$RootName,$DomainDN"
        $FinalPath  = $ParentPath

        if (-not [string]::IsNullOrWhiteSpace($ServiceClean)) {
            # On vérifie si l'OU Service existe, sinon on la crée
            $ServiceOUName = $ServiceClean # On garde le nom "joli" (ex: "Développement frontend")
            $FinalPath = "OU=$ServiceOUName,$ParentPath"
            
            if (!(Get-ADOrganizationalUnit -Filter "Name -eq '$ServiceOUName'" -SearchBase $ParentPath -ErrorAction SilentlyContinue)) {
                if (!$isDryRun) {
                    try {
                        New-ADOrganizationalUnit -Name $ServiceOUName -Path $ParentPath -ProtectedFromAccidentalDeletion $true
                        Write-Log "OU Service créée : $ServiceOUName" "INFO" -ConsoleOutput $false
                    } catch {
                        Write-Log "Erreur création OU Service $ServiceOUName" "ERROR" -ConsoleOutput $false
                    }
                }
            }
        }

        # 3. Gestion GROUPE (Fonction)
        $Fonction = ($Row.fonction -as [string]).Trim()
        $GroupsToAdd = @()
        if (-not [string]::IsNullOrWhiteSpace($Fonction)) {
            $GroupName = "GRP_" + $Fonction -replace '[^a-zA-Z0-9_-]', '' # Nettoyage simple nom groupe
            $GroupPath = "OU=$DeptCode,OU=RX,OU=$SiteName,OU=$RootName,$DomainDN" # Groupes dans RX > Dxx
            
            # Création du Groupe si inexistant
            if (!(Get-ADGroup -Filter "Name -eq '$GroupName'" -ErrorAction SilentlyContinue)) {
                if (!$isDryRun) {
                    try {
                        New-ADGroup -Name $GroupName -GroupScope Global -GroupCategory Security -Path $GroupPath
                        Write-Log "Groupe créé : $GroupName" "INFO" -ConsoleOutput $false
                    } catch {
                        # Si échec (ex: OU RX/Dxx pas prête), on logue
                        Write-Log "Erreur création Groupe $GroupName : $_" "ERROR" -ConsoleOutput $false
                    }
                }
            }
            $GroupsToAdd += $GroupName
        }

        # 4. Création User
        $SamAccountName = $IdBase
        # Gestion doublon basique
        $i=1
        while (Get-ADUser -Filter "SamAccountName -eq '$SamAccountName'" -ErrorAction SilentlyContinue) { $SamAccountName="$IdBase$i"; $i++ }

        if (Get-ADUser -Filter "SamAccountName -eq '$SamAccountName'" -ErrorAction SilentlyContinue) {
            $CountSkip++
        } else {
            if ($isDryRun) {
                Write-Log "SIMULATION : Création $SamAccountName dans $FinalPath (Grp: $GroupsToAdd)" "WARN" -ConsoleOutput $false
                $CountOK++
            } else {
                $Params = @{
                    SamAccountName = $SamAccountName
                    Name = "$Prenom $Nom"
                    GivenName = $Prenom; Surname = $Nom; DisplayName = "$Prenom $Nom"
                    EmailAddress = "$SamAccountName@ecotechsolutions.fr"
                    Path = $FinalPath
                    AccountPassword = $DefaultPwd
                    Enabled = $true
                    ChangePasswordAtLogon = $true
                    MobilePhone = (Get-FormatPhone ($Row."Telephone portable"))
                    Department = $Row.Departement
                    Title = $Row.fonction
                    Description = "Manager: $($Row.'Manager-Prenom') $($Row.'Manager-Nom')" # Info texte
                }
                try {
                    New-ADUser @Params
                    # Ajout au Groupe
                    foreach ($Grp in $GroupsToAdd) { Add-ADGroupMember -Identity $Grp -Members $SamAccountName -ErrorAction SilentlyContinue }
                    
                    Write-Log "Utilisateur créé : $SamAccountName" "SUCCESS" -ConsoleOutput $false
                    $CountOK++
                } catch {
                    Write-Log "Erreur création $SamAccountName : $_" "ERROR" -ConsoleOutput $false
                    $CountKO++
                }
            }
        }
    }
    # Résumé console
    Write-Host "------------------------------------------------" -ForegroundColor White
    Write-Host "RÉSULTAT SYNCHRO :" -ForegroundColor White
    Write-Host "Utilisateurs traités (ou simulés) : $CountOK" -ForegroundColor Green
    Write-Host "Erreurs                           : $CountKO" -ForegroundColor Red
    Write-Host "Déjà existants                    : $CountSkip" -ForegroundColor Yellow
    Write-Host "------------------------------------------------" -ForegroundColor White
}

function Sync-Managers {
    Write-Log "--- DÉBUT LIENS MANAGERS ---"
    if ($isDryRun) { Write-Host "Mode SIMULATION : Aucun lien ne sera créé." -ForegroundColor Yellow }
    
    $Users = Import-Csv -Path $CsvPath -Delimiter ";" -Encoding UTF8
    $CountLinks = 0
    $CountErr   = 0

    Write-Host "Mise à jour des managers en cours..." -ForegroundColor Cyan

    foreach ($Row in $Users) {
        $MgrPrenom = ($Row."Manager-Prenom" -as [string]).Trim()
        $MgrNom    = ($Row."Manager-Nom" -as [string]).Trim()

        # S'il n'y a pas de manager indiqué, on passe
        if ([string]::IsNullOrWhiteSpace($MgrNom)) { continue }

        # 1. Retrouver l'Employé (User)
        $UserLogin = Get-CalculatedLogin $Row.Prenom $Row.Nom
        # On cherche l'objet AD (au cas où il y a eu doublon et qu'il s'appelle user1)
        # Pour simplifier, on cherche par le SamAccountName théorique. 
        # En prod stricte, il faudrait stocker le matricule.
        $UserAD = Get-ADUser -Filter "SamAccountName -eq '$UserLogin'" -ErrorAction SilentlyContinue

        # 2. Retrouver le Manager (User)
        # On cherche par "Nom complet" (Display Name) car on a Prénom + Nom dans le CSV
        $MgrName = "$MgrPrenom $MgrNom"
        $MgrAD   = Get-ADUser -Filter "Name -eq '$MgrName'" -ErrorAction SilentlyContinue

        if ($UserAD -and $MgrAD) {
            if ($isDryRun) {
                Write-Log "SIMULATION : Lien $UserLogin -> Manager $MgrName" "INFO" -ConsoleOutput $false
                $CountLinks++
            } else {
                try {
                    Set-ADUser -Identity $UserAD -Manager $MgrAD
                    Write-Log "Lien OK : $UserLogin managé par $MgrName" "SUCCESS" -ConsoleOutput $false
                    $CountLinks++
                } catch {
                    Write-Log "Erreur lien $UserLogin : $_" "ERROR" -ConsoleOutput $false
                    $CountErr++
                }
            }
        } else {
            # Manager ou User introuvable
            if (!$UserAD) { Write-Log "Lien Impossible : Employé $UserLogin introuvable" "WARN" -ConsoleOutput $false }
            if (!$MgrAD)  { Write-Log "Lien Impossible : Manager $MgrName introuvable" "WARN" -ConsoleOutput $false }
            $CountErr++
        }
    }

    Write-Host "------------------------------------------------" -ForegroundColor White
    Write-Host "RÉSULTAT MANAGERS :" -ForegroundColor White
    Write-Host "Liens créés (ou simulés) : $CountLinks" -ForegroundColor Green
    Write-Host "Echecs / Introuvables    : $CountErr" -ForegroundColor Red
    Write-Host "------------------------------------------------" -ForegroundColor White
}

# =============================================================================
# 4. MENU
# =============================================================================
Clear-Host
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Admin requis !" -ForegroundColor Red; Exit
}

while ($true) {
    Write-Host "`n=== DEPLOIEMENT ECOTECH V7 (Manager & Services) ===" -ForegroundColor Cyan
    Write-Host "Mode Simulation : $(if($isDryRun){'ACTIF'} else {'INACTIF (Réel)'})" -ForegroundColor Yellow
    Write-Host "1. Basculer Mode Simulation"
    Write-Host "2. Créer Structure OUs (Infra)"
    Write-Host "3. Synchroniser Utilisateurs (+ Groupes & Services)"
    Write-Host "4. Lier les Managers (À faire après étape 3)"
    Write-Host "5. Quitter"
    
    $Choix = Read-Host "Votre choix"
    switch ($Choix) {
        "1" { $script:isDryRun = -not $script:isDryRun }
        "2" { New-InfraStructure }
        "3" { Sync-Users }
        "4" { Sync-Managers }
        "5" { Exit }
    }
}