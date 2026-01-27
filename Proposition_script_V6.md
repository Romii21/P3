# ALGORITHME : DEPLOIEMENT ECOTECH (V7 - Manager & Silent)

## 1. MENU
    AFFICHER "1. Mode Simulation (ON/OFF)"
    AFFICHER "2. Infra (OUs)"
    AFFICHER "3. Sync Users (Services + Groupes)"
    AFFICHER "4. Sync Managers (Liens hiérarchiques)"

## 2. FONCTION : Sync_Users()
    INIT Compteur_OK = 0, Compteur_KO = 0
    AFFICHER "Traitement en cours..."

    POUR CHAQUE Ligne CSV :
        
        // A. Calculs
        LOGIN = 2_Lettres_Prenom + Nom
        OU_SERVICE = "OU=" + Ligne.Service + ",OU=" + Dept...
        
        // B. Création OU Service (Si besoin)
        SI OU_SERVICE n'existe pas -> CRÉER

        // C. Création Groupe Fonction (Si besoin)
        GRP_NOM = "GRP_" + Ligne.Fonction
        SI GRP_NOM n'existe pas -> CRÉER dans RX
        
        // D. Création User
        SI User n'existe pas :
            CRÉER User
            AJOUTER User au Groupe GRP_NOM
            SI Succès -> Compteur_OK++
            SINON -> Compteur_KO++
        SINON :
            LOG "Déjà existant" (Dans fichier seulement)

    AFFICHER "Rapport : [Compteur_OK] créés / [Compteur_KO] erreurs."

## 3. FONCTION : Sync_Managers()
    INIT Compteur_Liens = 0
    AFFICHER "Mise à jour des liens hiérarchiques..."

    POUR CHAQUE Ligne CSV :
        
        SI Manager renseigné :
            EMPLOYE = Chercher User (Login calculé)
            CHEF    = Chercher User (Prénom + Nom du manager)

            SI EMPLOYE et CHEF existent :
                LITER "Manager" de EMPLOYE vers CHEF
                Compteur_Liens++
            SINON :
                LOG Erreur (Fichier seulement)
    
    AFFICHER "Terminé : [Compteur_Liens] managers liés."