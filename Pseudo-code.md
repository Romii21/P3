## 1. INITIALISATION ET SECURITE

    ### 1.1. Verif Admin (Bloquant)

    SI l'utilisateur courant N'EST PAS "Administrateur" ALORS
        AFFICHER "Erreur : Droits Admin requis."
        ARRETER le script
    FIN SI

    ### 1.2. Configuration

    MODE_SIMULATION = Vrai (Par defaut)
    FICHIER_LOG = "C:\Logs\Deploy_Date.log"

    ### 1.3. Mapping des Departements

    CARTE_DEPT = { "Ressources Humaines" -> "D01", "Finance" -> "D02", ... }

## 2. FONCTION : Ecrire_Log(Message, Niveau)

    ### 2.1. Gestion centralisee des traces

    ECRIRE "[Heure] [Niveau] Message" dans FICHIER_LOG
    Pas d'affichage console sauf pour le bilan final

## 3. FONCTION : Construire_Infra()

    POUR CHAQUE Niveau [Racine, Site(BDX), Types(UX, RX...)]
        SI Dossier n'existe pas : CREER Dossier
    FIN POUR

    POUR CHAQUE Code [D01...D07]
        CREER Sous-Dossier Code DANS "UX" (Pour Users)
        CREER Sous-Dossier Code DANS "RX" (Pour Groupes)
    FIN POUR

## 4. FONCTION : Synchro_Utilisateurs()

    Lire le CSV

    Etape A : Cartographie Services (S01, S02...)
    TRIER Services et ATTRIBUER Codes Sxx

    POUR CHAQUE Ligne du CSV :
        
        ### 4.1. Calculs de Base

        PRENOM = Nettoyer(Ligne.Prenom)
        NOM    = Nettoyer(Ligne.Nom)
        DEPT   = Mapping[Ligne.Departement]
        SVC    = Code Sxx calcule
        
        ### 4.2. Calcul du Login avec Gestion Doublons (Boucle)

        BASE_LOGIN = (2 lettres Prenom) + Nom
        LOGIN_FINAL = BASE_LOGIN
        COMPTEUR = 1
        
        TANT QUE (Compte AD [LOGIN_FINAL] existe) FAIRE
            // C'est un doublon ! On ajoute un chiffre.
            LOGIN_FINAL = BASE_LOGIN + COMPTEUR
            INCREMENTER COMPTEUR
        FIN TANT QUE
        
        ## 4.3. Chemins AD

        CHEMIN_USER = "OU=[SVC],OU=[DEPT],OU=UX..."
        
        ## 4.4. Groupes (Naming strict)

        NOM_GRP = "ECO-BDX-RX-G-" + [DEPT] + "-" + Nettoyer(Fonction)
        SI Groupe manque : CREER Groupe
        
        ## 4.5. Creation ou Mise a jour

        TRY :
            SI Mode Simulation :
                LOG "Simulation creation [LOGIN_FINAL]"
            SINON :
                CREER User :
                    - SamAccountName = LOGIN_FINAL
                    - Telephone = Colonne "Telephone fixe" (05...)
                AJOUTER a Groupe [NOM_GRP]
                INCREMENTER Compteur_Succes
        CATCH :
            INCREMENTER Compteur_Erreurs
            LOG Erreur
            
    FIN POUR

    AFFICHER "Termine. Succes: [X], Erreurs: [Y]." (Sans accents)

## 5. FONCTION : Synchro_Managers()

    Identique : Lie les comptes apres creation

    POUR CHAQUE Ligne :
        SI Manager et Employe existent : LIER dans AD
    FIN POUR
    AFFICHER "Liens Managers effectues."