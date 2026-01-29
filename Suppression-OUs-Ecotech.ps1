# 1. On cible la racine ECOTECH
$TargetOU = "OU=ECOTECH,DC=ecotech,DC=local"

# 2. On désactive la protection sur la racine et TOUS les sous-dossiers
Get-ADOrganizationalUnit -SearchBase $TargetOU -Filter * | Set-ADOrganizationalUnit -ProtectedFromAccidentalDeletion $false

# 3. On supprime tout récursivement
Remove-ADOrganizationalUnit -Identity $TargetOU -Recursive -Confirm:$false

Write-Host "Nettoyage terminé ! L'OU ECOTECH a été supprimée." -ForegroundColor Green