<#
Synchro_Ecotech

Création d'un script de synchronisation d'un fichier "Fiche_Perosnnel.csv",
Ce script permet de récuperer les informations liées aux profils du personnel.
Le script agis en plusieurs phase qui se suivent :
    - Créeation des OUs selon le fichier naming.md de notre Documentation.
    - Synchronisation des employés et des groupes du fichier "Fiche_personnel.csv" :
        - Les employés sont rangés dans le bon département (D01, D02, etc.).
        - Ils sont ensuite envoyé dans le le bon service (S01, S02, etc.).
        - Même principe pour les groupes, il sont liés au département puis au service.
    - Synchronisation des managers.
    - Sortie
#>

# =============================================================================
# 1. Vérification des droits (Admin)
# =============================================================================

# On recupere l'identite de celui qui lance le script

#$CurrentId = [Security.Principal.WindowsIdentity]::GetCurrent()
#$Principal = New-Object Security.Principal.WindowsPrincipal($CurrentId)

# Si ce n'est pas un admin, on arrete tout immediatement

#if (-not $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
#    Write-Host "ERREUR : Vous devez lancer ce script en tant qu'Administrateur." -ForegroundColor Red
#    Start-Sleep -Seconds 3
#    Exit
#}

# =============================================================================
# 2. Configuration du script
# =============================================================================

# --- Parametres generaux ---

$isDryRun   = $true                    # $true = Simulation (rien n'est cree), $false = Reel
$DomainDN   = "DC=ecotech,DC=local"    # Base du domaine
$RootName   = "ECOTECH"                # Nom de la racine
$SiteName   = "BDX"                    # Code du site (Bordeaux)

# Fichiers source
# Le fichier CSV doit etre dans le meme dossier que le script (à modifier)

$CsvPath    = "$PSScriptRoot\Fiche_personnels.csv"

# Emplacement Logs

$LogFile    = "C:\Logs\EcoTech_Deploy_$(Get-Date -Format 'yyyyMMdd_HHmm').log"

# MDP de base

$DefaultPwd = ConvertTo-SecureString "EcoTech2026!" -AsPlainText -Force

# Mapping OUs
# Utilise les départments du fichier "Fiche_personnel.csv" et les converties selon notre Documentation

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
# 3. Les Fonctions
# =============================================================================

# Permet d'avoir un suivis des opérations effectuer dans le script

function Write-Log {

    # Ecrit un message dans le fichier texte C:\Logs\...

    param([string]$Message, [string]$Level="INFO")
    
    # Cree le dossier Logs s'il n'existe pas

    $LogDir = Split-Path $LogFile -Parent
    if (!(Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }
    
    # Formate la ligne : [Heure] [Niveau] Message

    $Line = "[$(Get-Date -Format 'HH:mm:ss')] [$Level] $Message"
    Add-Content -Path $LogFile -Value $Line
}

# Normalisation des carractères du fichier "Fiche_personnel.csv".

function Get-CleanString {

    # Nettoie une chaine : minuscule, sans accents, sans espaces
    # Ex: "Développement Web" -> "developpementweb"

    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return "" }
    
    # Normalisation (separation des accents) et suppression

    $Text = $Text.ToLower().Normalize([System.Text.NormalizationForm]::FormD) -replace '\p{Mn}', ''
    return $Text -replace '[^a-z0-9]', ''

}

# Normalisation du format des numéros de téléphone,
# Les téléphones sont bien configurés dans le fichier "Fiche_personnel.csv",
# Mais nous voulons que si des nouveaux numéros sont ajoutés, ils soient au bon format.

function Get-FormatPhone {

    param([string]$Phone)
    $Digits = $Phone -replace '[^0-9]', ''
    
    if ($Digits.Length -eq 10 -and $Digits.StartsWith("0")) { 
        return "+33 " + $Digits.Substring(1) 
    }
    return $Phone

}

# Génération du login de l'utilisateur, comme indiqué dans la documentation.
# Ex: Prenom = "Jean", Nom = "Dupont" -> Login = "jedupont"

function Get-CalculatedLogin {

    # Genere l'ID : 2 premieres lettres du Prenom + Nom complet

    param($Prenom, $Nom)
    
    # Nettoyage prealable des entrees

    $Prenom = ($Prenom -as [string]).Trim()
    $Nom    = ($Nom -as [string]).Trim()
    
    if ($Prenom.Length -ge 2) { 
        $P2 = $Prenom.Substring(0,2) 
    } else { 
        $P2 = $Prenom 
    }
    
    return Get-CleanString ($P2 + $Nom)

}

# =============================================================================
# 4. L'architecture des OUs.
# =============================================================================

function Build-ServiceMap {

    # Cette fonction lit tout le CSV pour attribuer les codes S01, S02...

    param($UsersData)
    
    # Variable globale pour stocker le resultat (accessible partout)

    $Global:ServiceCodeMap = @{}
    
    # On regroupe les utilisateurs par Departement

    $Grouped = $UsersData | Group-Object Departement
    
    foreach ($DeptGroup in $Grouped) {

        # On trouve le code Dxx du departement

        $DeptCode = $DeptMap[(Get-CleanString $DeptGroup.Name)]
        if (-not $DeptCode) { continue }
        
        # On liste les services UNIQUES de ce departement et on les trie

        $UniqueServices = $DeptGroup.Group | Select-Object -ExpandProperty Service -Unique | Sort-Object
        
        $Counter = 1
        foreach ($Svc in $UniqueServices) {
            $SvcClean = ($Svc -as [string]).Trim()
            if ([string]::IsNullOrWhiteSpace($SvcClean)) { continue }
            
            # On genere le code S01, S02...

            $SCode = "S{0:D2}" -f $Counter
            
            # On stocke dans la map : "D05-frontend" = "S01"

            $Global:ServiceCodeMap["$DeptCode-" + (Get-CleanString $SvcClean)] = $SCode
            
            $Counter++
        }
    }
}

# Mise en place de l'infrastructure AD (OUs)
# Selon le fichier naming.md de la documentation
# Structure :
#  - ECOTECH
#     - BDX
#        - GX
#        - UX
#           - D01
#             - S01
#             - S02
#           - D02
#           - ...
#        - RX
#           - D01
#             - S01
#             - S02 
#           - D02
#           - ...

function New-InfraStructure {

    Write-Host "Verification de l'infrastructure..." -ForegroundColor Cyan
    Write-Log "Creation de l'infrastructure AD..."
    
    # On cree les dossiers un par un, du haut vers le bas
    
    # 1. Racine ECOTECH

    if (!(Get-ADOrganizationalUnit -Filter "Name -eq '$RootName'" -SearchBase $DomainDN -ErrorAction SilentlyContinue)) {
        if (!$isDryRun) { 
            try { New-ADOrganizationalUnit -Name $RootName -Path $DomainDN -ProtectedFromAccidentalDeletion $true } catch {} 
        }
    }
    
    # 2. Site BDX

    $PathRoot = "OU=$RootName,$DomainDN"
    if (!(Get-ADOrganizationalUnit -Filter "Name -eq '$SiteName'" -SearchBase $PathRoot -ErrorAction SilentlyContinue)) {
        if (!$isDryRun) { 
            try { New-ADOrganizationalUnit -Name $SiteName -Path $PathRoot -ProtectedFromAccidentalDeletion $true } catch {} 
        }
    }

    # 3. Types (GX, UX, RX, WX)

    $PathSite = "OU=$SiteName,$PathRoot"
    foreach ($Type in @("GX","UX","RX","WX")) {
        if (!(Get-ADOrganizationalUnit -Filter "Name -eq '$Type'" -SearchBase $PathSite -ErrorAction SilentlyContinue)) {
             if (!$isDryRun) { New-ADOrganizationalUnit -Name $Type -Path $PathSite -ProtectedFromAccidentalDeletion $true }
        }
    }
    
    # 4. Departements (D01...D07) dans UX et RX

    foreach ($Parent in @("UX", "RX")) {
        foreach ($Code in $DeptMap.Values) {
            $Path = "OU=$Parent,$PathSite"
            if (!(Get-ADOrganizationalUnit -Filter "Name -eq '$Code'" -SearchBase $Path -ErrorAction SilentlyContinue)) {
                if (!$isDryRun) { New-ADOrganizationalUnit -Name $Code -Path $Path -ProtectedFromAccidentalDeletion $true }
            }
        }
    }
    
    Write-Host " Termine." -ForegroundColor Green
}

# =============================================================================
# 5. Synchronisation des utilisateurs et groupes
# =============================================================================

function Sync-Users {

    Write-Host "Traitement des utilisateurs et groupes..." -ForegroundColor Cyan
    Write-Log "Synchronisation des utilisateurs et groupes..."
    
    if (!(Test-Path $CsvPath)) { return }
    
    # Lecture du CSV avec encodage UTF8 pour les accents

    $Users = Import-Csv -Path $CsvPath -Delimiter ";" -Encoding UTF8
    
    # Calcul des codes Sxx avant de commencer

    Build-ServiceMap -UsersData $Users
    
    # Initialisation des statistiques

    $Stats = @{ OK=0; KO=0; Skip=0 }

    foreach ($Row in $Users) {

        # Nettoyage de base

        $Prenom = ($Row.Prenom -as [string]).Trim()
        $Nom    = ($Row.Nom -as [string]).Trim()
        if ([string]::IsNullOrWhiteSpace($Nom)) { continue }

        # Suis la fonction Get-CalculatedLogin pour generer le login de base

        $IdBase   = Get-CalculatedLogin $Prenom $Nom
        $DeptCode = $DeptMap[(Get-CleanString $Row.Departement)]
        
        if (-not $DeptCode) { $Stats.KO++; continue }

        # Determination du chemin final de l'utilisateur

        $SvcClean    = ($Row.Service -as [string]).Trim()
        $FinalPath   = "OU=$DeptCode,OU=UX,OU=$SiteName,OU=$RootName,$DomainDN"
        $GroupsToAdd = @()

        if (-not [string]::IsNullOrWhiteSpace($SvcClean)) {

            # On recupere le code Sxx (ex: S01)

            $KeyMap = "$DeptCode-" + (Get-CleanString $SvcClean)
            $SCode  = $Global:ServiceCodeMap[$KeyMap]

            if ($SCode) {

                # 1. Creation OU Service si elle manque

                $FinalPath = "OU=$SCode,$FinalPath"
                $ParentOU  = "OU=$DeptCode,OU=UX,OU=$SiteName,OU=$RootName,$DomainDN"
                
                if (!(Get-ADOrganizationalUnit -Filter "Name -eq '$SCode'" -SearchBase $ParentOU -ErrorAction SilentlyContinue)) {
                    if (!$isDryRun) { 
                        try { New-ADOrganizationalUnit -Name $SCode -Path $ParentOU -Description $SvcClean -ProtectedFromAccidentalDeletion $true } catch {} 
                    }
                }

                # 2. Gestion du Groupe, Naming : GRP-UX-Dxx-Sxx

                $GrpName = "GRP-UX-$DeptCode-$SCode"
                $GrpPath = "OU=$DeptCode,OU=RX,OU=$SiteName,OU=$RootName,$DomainDN" # Range dans RX
                
                if (!(Get-ADGroup -Filter "Name -eq '$GrpName'" -ErrorAction SilentlyContinue)) {
                    if (!$isDryRun) { 
                        try { New-ADGroup -Name $GrpName -GroupScope Global -GroupCategory Security -Path $GrpPath -Description "Groupe Service $SvcClean" } catch {} 
                    }
                }
                $GroupsToAdd += $GrpName
            }
        }

        # Gestion des doublons
        # Un utilisateur part sur la base de 1, puis si le login existe deja, on ajoute 1, 2, 3...

        $SamAccountName = $IdBase
        $Counter = 1

        # Tant que le compte existe deja dans l'AD, on ajoute 1, 2, 3...

        while (Get-ADUser -Filter "SamAccountName -eq '$SamAccountName'" -ErrorAction SilentlyContinue) { 
            $SamAccountName = "$IdBase$Counter"
            $Counter++ 
        }

        # Creation de l'utilisateur avec leurs parametres
        
        if ($isDryRun) {
            Write-Log "SIMULATION : Creation $SamAccountName (Grp: $GroupsToAdd)" "WARN"
            $Stats.OK++
        } 
        
        else {

            # Definition des parametres

            $Params = @{
                
                SamAccountName        = $SamAccountName
                Name                  = "$Prenom $Nom"
                GivenName             = $Prenom
                Surname               = $Nom
                DisplayName           = "$Prenom $Nom"
                EmailAddress          = "$SamAccountName@ecotechsolutions.fr"
                Path                  = $FinalPath
                AccountPassword       = $DefaultPwd
                Enabled               = $true
                ChangePasswordAtLogon = $true
                OfficePhone           = (Get-FormatPhone ($Row."Telephone fixe")) # Fixe 05
                Department            = $Row.Departement
                Title                 = $Row.fonction
                Description           = "Manager: $($Row.'Manager-Prenom') $($Row.'Manager-Nom')"
            }
            
            # Execution

            try {

                New-ADUser @Params

                # Ajout aux groupes calcules

                foreach ($Grp in $GroupsToAdd) { 
                    Add-ADGroupMember -Identity $Grp -Members $SamAccountName -ErrorAction SilentlyContinue 
                }

                $Stats.OK++
            } 
            
            catch {
                Write-Log "ERREUR sur $SamAccountName : $_" "ERROR"
                $Stats.KO++
            }
        }
    }
    
    # Un bilan sera plus simple à lire que tout les validations, erreurs et skips affichés en temps normal.

    Write-Host "Bilan : $($Stats.OK) Succes | $($Stats.KO) Erreurs" -ForegroundColor White
}

# =============================================================================
# 6. Synchronisation des Managers
# =============================================================================

function Sync-Managers {

    Write-Host "Liaison des Managers..." -NoNewline
    Write-Log "--- DEBUT MANAGERS ---"
    
    $Users = Import-Csv -Path $CsvPath -Delimiter ";" -Encoding UTF8
    $Links = 0
    
    foreach ($Row in $Users) {
        if ([string]::IsNullOrWhiteSpace($Row."Manager-Nom")) { continue }
        
        # On tente de retrouver l'employe et son manager

        $UserLogin = Get-CalculatedLogin $Row.Prenom $Row.Nom
        $UserAD    = Get-ADUser -Filter "SamAccountName -eq '$UserLogin'" -ErrorAction SilentlyContinue
        
        $MgrName   = "$($Row.'Manager-Prenom') $($Row.'Manager-Nom')"
        $MgrAD     = Get-ADUser -Filter "Name -eq '$MgrName'" -ErrorAction SilentlyContinue

        if ($UserAD -and $MgrAD) {
            if (!$isDryRun) { 
                try { Set-ADUser -Identity $UserAD -Manager $MgrAD -ErrorAction SilentlyContinue; $Links++ } catch {} 
            } else { 
                $Links++ 
            }
        }
    }
    Write-Host " $Links liens effectues." -ForegroundColor Green
}

# =============================================================================
# 7. Menu Principal
# =============================================================================

Clear-Host
while ($true) {
    Write-Host ""
    Write-Host "################################################################" -ForegroundColor DarkCyan
    Write-Host "################################################################" -ForegroundColor DarkCyan
    Write-Host "####                                                        ####" -ForegroundColor DarkCyan
    Write-Host "####                    Synchro-Ecotech                     ####" -ForegroundColor DarkCyan
    Write-Host "####                                                        ####" -ForegroundColor DarkCyan
    Write-Host "################################################################" -ForegroundColor DarkCyan
    Write-Host "################################################################" -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "Un mode de SIMULATION est disponible pour tester le script sans rien creer dans l'AD." -ForegroundColor Cyan
    Write-Host ""
    Write-Host "s. Basculer Mode (Simu/Reel)"
    Write-Host ""
    Write-Host "Mode Actuel : $(if($isDryRun){'SIMULATION'} else {'REEL'})" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Le script realise les actions suivantes, elles devront etre faites dans cet ordre :" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "1. Verifier Infrastructure"
    Write-Host "2. Synchroniser Users & Groupes"
    Write-Host "3. Lier Managers"
    Write-Host "4. Quitter"

    $Choix = Read-Host "Votre Choix"
    
    switch ($Choix) {
        "s" { $script:isDryRun = -not $script:isDryRun }
        "1" { New-InfraStructure }
        "2" { Sync-Users }
        "3" { Sync-Managers }
        "4" { Exit }
    }
}