# =============================================================================
# 1. INITIALISATION ET SECURITE
# =============================================================================

# Verification Droits Administrateur

$CurrentId = [Security.Principal.WindowsIdentity]::GetCurrent()
$Principal = New-Object Security.Principal.WindowsPrincipal($CurrentId)
if (-not $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERREUR : Droits Administrateur requis. Relancez en tant qu'Admin." -ForegroundColor Red
    Start-Sleep -Seconds 3
    Exit
}

# Configuration

$isDryRun   = $true # Par defaut en Simulation
$DomainDN   = "DC=ecotech,DC=local"
$RootName   = "ECOTECH"
$SiteName   = "BDX"
$LogFile    = "C:\Logs\EcoTech_Deploy_$(Get-Date -Format 'yyyyMMdd_HHmm').log"
$CsvPath    = "$PSScriptRoot\Fiche_personnels.csv"
$DefaultPwd = ConvertTo-SecureString "EcoTech2026!" -AsPlainText -Force

# Mapping Departements (Nom CSV -> Code Dxx)

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

    param([string]$Message, [string]$Level="INFO")
    
    # Creation dossier logs si absent

    $LogDir = Split-Path $LogFile -Parent
    if (!(Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }
    
    $Time = Get-Date -Format "HH:mm:ss"
    $Line = "[$Time] [$Level] $Message"
    
    # Ecriture fichier uniquement (Pas d'echo console pour respecter le silence)

    Add-Content -Path $LogFile -Value $Line
}

function Get-CleanString {

    # Nettoie accents et speciaux pour usage technique

    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return "" }
    $Text = $Text.ToLower().Normalize([System.Text.NormalizationForm]::FormD) -replace '\p{Mn}', ''
    return $Text -replace '[^a-z0-9]', ''
}

function Get-FormatPhone {

    # Formate le telephone fixe (05...)

    param([string]$Phone)
    $Digits = $Phone -replace '[^0-9]', ''
    if ($Digits.Length -eq 10 -and $Digits.StartsWith("0")) {
        return "+33 " + $Digits.Substring(1)
    }
    return $Phone
}

function Get-CalculatedLogin {

    # 2 lettres Prenom + Nom

    param($Prenom, $Nom)
    $Prenom = ($Prenom -as [string]).Trim()
    $Nom    = ($Nom -as [string]).Trim()
    if ($Prenom.Length -ge 2) { $P2 = $Prenom.Substring(0,2) } 
    else { $P2 = $Prenom }
    return Get-CleanString ($P2 + $Nom)
}

# =============================================================================
# 3. FONCTIONS METIER
# =============================================================================

function Build-ServiceMap {

    param($UsersData)

    # Analyse silencieuse du CSV pour attribuer les codes Sxx

    $Global:ServiceCodeMap = @{}
    
    $Grouped = $UsersData | Group-Object Departement
    foreach ($DeptGroup in $Grouped) {
        $DeptClean = Get-CleanString $DeptGroup.Name
        $DeptCode  = $DeptMap[$DeptClean]
        if (-not $DeptCode) { continue }

        $UniqueServices = $DeptGroup.Group | Select-Object -ExpandProperty Service -Unique | Sort-Object
        $Counter = 1
        foreach ($SvcName in $UniqueServices) {
            $SvcClean = ($SvcName -as [string]).Trim()
            if ([string]::IsNullOrWhiteSpace($SvcClean)) { continue }
            
            # Code S01, S02...
            $SCode = "S{0:D2}" -f $Counter
            $KeyMap = "$DeptCode-" + (Get-CleanString $SvcClean)
            $Global:ServiceCodeMap[$KeyMap] = $SCode
            $Counter++
        }
    }
}

function New-InfraStructure {

    Write-Host "Verification de l'infrastructure..." -NoNewline
    Write-Log "--- DEBUT INFRASTRUCTURE ---"
    
    # Construction sequentielle (Racine -> Site -> Types -> Depts)
    
    # 1. Racine

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

    # 3. Types

    $PathSite = "OU=$SiteName,$PathRoot"
    foreach ($Type in @("GX","UX","RX","WX")) {
        if (!(Get-ADOrganizationalUnit -Filter "Name -eq '$Type'" -SearchBase $PathSite -ErrorAction SilentlyContinue)) {
             if (!$isDryRun) { New-ADOrganizationalUnit -Name $Type -Path $PathSite -ProtectedFromAccidentalDeletion $true }
        }
    }
    
    # 4. Departements

    foreach ($Parent in @("UX", "RX")) {
        foreach ($Code in $DeptMap.Values) {
            $Path = "OU=$Parent,$PathSite"
            if (!(Get-ADOrganizationalUnit -Filter "Name -eq '$Code'" -SearchBase $Path -ErrorAction SilentlyContinue)) {
                if (!$isDryRun) { New-ADOrganizationalUnit -Name $Code -Path $Path -ProtectedFromAccidentalDeletion $true }
            }
        }
    }
    
    Write-Host " OK." -ForegroundColor Green
    Write-Log "Infra verifiee."
}

function Sync-Users {

    Write-Host "Synchronisation Utilisateurs en cours..." -ForegroundColor Cyan
    Write-Log "--- DEBUT SYNCHRO USERS ---"
    
    if (!(Test-Path $CsvPath)) { Write-Host "Erreur: CSV introuvable." -ForegroundColor Red; return }
    $Users = Import-Csv -Path $CsvPath -Delimiter ";" -Encoding UTF8
    
    # Preparation des codes Sxx

    Build-ServiceMap -UsersData $Users

    $Stats = @{ Success=0; Errors=0; Skipped=0 }

    foreach ($Row in $Users) {
        $Prenom = ($Row.Prenom -as [string]).Trim()
        $Nom    = ($Row.Nom -as [string]).Trim()
        if ([string]::IsNullOrWhiteSpace($Nom)) { continue }

        # --- Calculs ---
        $IdBase    = Get-CalculatedLogin $Prenom $Nom
        $DeptClean = Get-CleanString ($Row.Departement)
        $DeptCode  = $DeptMap[$DeptClean]
        
        if (-not $DeptCode) { 
            Write-Log "Dept Inconnu : $($Row.Departement)" "WARN"
            $Stats.Errors++
            continue 
        }

        # --- OU Cible (Sxx) ---

        $ServiceClean = ($Row.Service -as [string]).Trim()
        $FinalPath    = "OU=$DeptCode,OU=UX,OU=$SiteName,OU=$RootName,$DomainDN"

        if (-not [string]::IsNullOrWhiteSpace($ServiceClean)) {
            $KeyMap = "$DeptCode-" + (Get-CleanString $ServiceClean)
            $ServiceCode = $Global:ServiceCodeMap[$KeyMap] 

            if ($ServiceCode) {
                $FinalPath = "OU=$ServiceCode,$FinalPath"

                # Creation OU Service Sxx si manquante

                if (!(Get-ADOrganizationalUnit -Filter "Name -eq '$ServiceCode'" -SearchBase "OU=$DeptCode,OU=UX,OU=$SiteName,OU=$RootName,$DomainDN" -ErrorAction SilentlyContinue)) {
                    if (!$isDryRun) {
                        try { New-ADOrganizationalUnit -Name $ServiceCode -Path "OU=$DeptCode,OU=UX,OU=$SiteName,OU=$RootName,$DomainDN" -Description $ServiceClean -ProtectedFromAccidentalDeletion $true } catch {}
                    }
                }
            }
        }

        # --- Groupe Fonction (Naming Strict) ---

        $Fonction = ($Row.fonction -as [string]).Trim()
        $GroupsToAdd = @()
        if (-not [string]::IsNullOrWhiteSpace($Fonction)) {

            # Format : ECO-BDX-RX-G-[Dept]-[Fonction]

            $FctClean = Get-CleanString $Fonction
            $GroupName = "ECO-BDX-RX-G-$DeptCode-$FctClean"
            $GroupPath = "OU=$DeptCode,OU=RX,OU=$SiteName,OU=$RootName,$DomainDN"
            
            # Creation Groupe
            if (!(Get-ADGroup -Filter "Name -eq '$GroupName'" -ErrorAction SilentlyContinue)) {
                if (!$isDryRun) {
                     try { New-ADGroup -Name $GroupName -GroupScope Global -GroupCategory Security -Path $GroupPath } catch {}
                }
            }
            $GroupsToAdd += $GroupName
        }

        # --- Gestion Doublon (Login+1) ---

        $SamAccountName = $IdBase
        $Counter = 1

        # Tant que le compte existe dans l'AD, on incremente

        while (Get-ADUser -Filter "SamAccountName -eq '$SamAccountName'" -ErrorAction SilentlyContinue) { 
            $SamAccountName = "$IdBase$Counter"
            $Counter++
        }

        # --- Creation User ---
        
        if ($isDryRun) {
            Write-Log "SIMULATION : Creation $SamAccountName" "WARN"
            $Stats.Success++ # On compte comme succes simule
        } 
        
        else {
            $Params = @{
                SamAccountName = $SamAccountName
                Name           = "$Prenom $Nom"
                GivenName      = $Prenom
                Surname        = $Nom
                DisplayName    = "$Prenom $Nom"
                EmailAddress   = "$SamAccountName@ecotechsolutions.fr"
                Path           = $FinalPath
                AccountPassword = $DefaultPwd
                Enabled        = $true
                ChangePasswordAtLogon = $true
                OfficePhone    = (Get-FormatPhone ($Row."Telephone fixe")) # Fixe uniquement
                Department     = $Row.Departement
                Title          = $Row.fonction
                Description    = "Manager: $($Row.'Manager-Prenom') $($Row.'Manager-Nom')"
            }
            
            try {
                New-ADUser @Params

                # Ajout Groupes

                foreach ($Grp in $GroupsToAdd) { Add-ADGroupMember -Identity $Grp -Members $SamAccountName -ErrorAction SilentlyContinue }
                
                Write-Log "OK : $SamAccountName cree" "SUCCESS"
                $Stats.Success++
            } 
            
            catch {
                Write-Log "ERREUR $SamAccountName : $_" "ERROR"
                $Stats.Errors++
            }
        }
    }
    
    # Bilan compact

    Write-Host "-----------------------------" -ForegroundColor White
    Write-Host "BILAN UTILISATEURS :" -ForegroundColor White
    Write-Host "Traités : $($Stats.Success)" -ForegroundColor Green
    Write-Host "Erreurs : $($Stats.Errors)" -ForegroundColor Red
    Write-Host "-----------------------------" -ForegroundColor White
}

function Sync-Managers {
    Write-Host "Liaison des Managers en cours..." -NoNewline
    Write-Log "--- DEBUT MANAGERS ---"
    
    $Users = Import-Csv -Path $CsvPath -Delimiter ";" -Encoding UTF8
    $Links = 0
    
    foreach ($Row in $Users) {
        if ([string]::IsNullOrWhiteSpace($Row."Manager-Nom")) { continue }
        
        # On recalcule l'ID theorique (Attention : si doublon +1, le lien peut echouer ici sans matricule unique)
        # Dans ce script simplifie, on tente le login de base.

        $UserLogin = Get-CalculatedLogin $Row.Prenom $Row.Nom
        $UserAD = Get-ADUser -Filter "SamAccountName -eq '$UserLogin'" -ErrorAction SilentlyContinue
        
        $MgrName = "$($Row.'Manager-Prenom') $($Row.'Manager-Nom')"
        $MgrAD   = Get-ADUser -Filter "Name -eq '$MgrName'" -ErrorAction SilentlyContinue

        if ($UserAD -and $MgrAD) {
            if (!$isDryRun) { 
                try { Set-ADUser -Identity $UserAD -Manager $MgrAD -ErrorAction SilentlyContinue; $Links++ } catch {}
            } else {
                $Links++
            }
        }
    }
    Write-Host " $Links liens verifies." -ForegroundColor Green
}

# =============================================================================
# 4. MENU PRINCIPAL
# =============================================================================

Clear-Host
while ($true) {
    Write-Host "`n=== DEPLOIEMENT ECOTECH V11 ===" -ForegroundColor Cyan
    Write-Host "Mode : $(if($isDryRun){'SIMULATION'} else {'REEL'})" -ForegroundColor Yellow
    Write-Host "1. Basculer Mode (Simu/Reel)"
    Write-Host "2. Verifier Infrastructure"
    Write-Host "3. Synchroniser Tout (Users, Groupes)"
    Write-Host "4. Lier Managers"
    Write-Host "5. Quitter"
    
    $Choix = Read-Host "Choix"
    switch ($Choix) {
        "1" { $script:isDryRun = -not $script:isDryRun }
        "2" { New-InfraStructure }
        "3" { Sync-Users }
        "4" { Sync-Managers }
        "5" { Exit }
    }
}